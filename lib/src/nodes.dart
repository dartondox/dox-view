import 'dart:collection';
import 'dart:math';

import 'expression.dart';
import 'safe_string.dart';
import 'scope.dart';
import 'view_engine.dart';
import 'view_exception.dart';

/// A parsed template.
class Template {
  const Template(this.name, this.nodes, [this.layout]);

  final String name;
  final List<Node> nodes;

  /// the `@extends` of the template, null when it has no layout
  final ExtendsNode? layout;
}

/// The state of one render.
class RenderContext {
  RenderContext(this.engine, this.shared);

  final ViewEngine engine;

  /// the globals and the shared data of this render. Components see it.
  final Scope shared;

  /// the template that renders now, for error messages
  String template = '';
  int _depth = 0;

  /// the `@once` blocks that rendered already
  final Set<String> once = <String>{};

  /// the content of each `@section`, by name
  final Map<String, String> sections = <String, String>{};

  /// the content of each `@push`, by the name of the stack
  final Map<String, List<String>> stacks = <String, List<String>>{};

  /// the names of the stacks with a `@stack` in the output
  final Set<String> _stackNames = <String>{};

  static final Random _random = Random.secure();

  /// the start of the mark that `@stack` leaves in the output. It has a
  /// random number of this render, so text from the user can not be a mark.
  late final String _mark =
      '\u0000stack${_random.nextInt(1 << 32)}'
      '${_random.nextInt(1 << 32)}${_random.nextInt(1 << 32)}:';

  /// the mark of `@stack(name)`. [finish] puts the pushes there, so a
  /// `@push` that renders after the `@stack` is in it too.
  String stackMark(String name) {
    _stackNames.add(name);
    return '$_mark$name\u0000';
  }

  /// [html] with every `@stack` filled. A push can have a `@stack` in
  /// it, so this runs again while a mark is left. A stack that pushes
  /// to itself would never end: after 10 rounds the marks still left
  /// are removed. So a mark never reaches the browser.
  String finish(String html) {
    if (_stackNames.isEmpty) return html;
    for (int round = 0; round < 10 && html.contains(_mark); round++) {
      for (String name in _stackNames) {
        html = html.replaceAll('$_mark$name\u0000', stacks[name]?.join() ?? '');
      }
    }
    if (!html.contains(_mark)) return html;
    return html.replaceAll(
      RegExp('${RegExp.escape(_mark)}[^\u0000]*\u0000'),
      '',
    );
  }

  /// the text of [value] for the output: escaped, but not a `SafeString`
  String escape(Object? value) =>
      value is SafeString ? value.value : escapeHtml(text(value));

  /// the text of [value] for the output, not escaped. With
  /// `bladeOutput`, `true` is `1`, `false` is empty and `10.0` is `10`.
  String text(Object? value) {
    if (engine.bladeOutput) {
      if (value is bool) return value ? '1' : '';
      if (value is double) {
        String text = value.toString();
        return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
      }
    }
    return stringify(value);
  }

  /// [nodes] as text
  String capture(List<Node> nodes, Scope scope) {
    StringBuffer out = StringBuffer();
    renderNodes(nodes, scope, out);
    return out.toString();
  }

  /// [expr], with the template and [line] in any error
  Object? eval(Expr expr, Scope scope, int line) {
    try {
      return expr.evaluate(scope);
    } on ViewException catch (error) {
      if (error.template != null) rethrow;
      throw ViewException(error.message, template: template, line: line);
    } on Object catch (error) {
      throw ViewException('$error', template: template, line: line);
    }
  }

  void renderTemplate(String name, Scope scope, StringBuffer out, int line) {
    // a template that includes itself would never end
    if (_depth >= 100) {
      throw ViewException(
        'too many nested templates at "$name". '
        'Does a template include or extend itself?',
        template: template,
        line: line,
      );
    }
    Template found;
    try {
      found = engine.template(name);
    } on ViewException catch (error) {
      if (error.template != null) rethrow;
      throw ViewException(error.message, template: template, line: line);
    }
    String parent = template;
    template = name;
    _depth++;
    try {
      ExtendsNode? layout = found.layout;
      if (layout == null) {
        renderNodes(found.nodes, scope, out);
      } else {
        // the template fills its sections first. Its text outside a
        // section is dropped. Then the layout prints the sections.
        // ponytail: the dropped text is still rendered into a buffer
        capture(found.nodes, scope);
        Object? parentName = eval(layout.name, scope, layout.line);
        if (parentName is! String) {
          throw ViewException(
            '@extends needs a template name',
            template: name,
            line: layout.line,
          );
        }
        renderTemplate(
          parentName,
          Scope(<String, Object?>{}, scope),
          out,
          layout.line,
        );
      }
    } finally {
      template = parent;
      _depth--;
    }
  }

  void renderNodes(List<Node> nodes, Scope scope, StringBuffer out) {
    for (Node node in nodes) {
      node.render(this, scope, out);
    }
  }
}

abstract class Node {
  const Node(this.line);

  final int line;

  void render(RenderContext ctx, Scope scope, StringBuffer out);
}

class TextNode extends Node {
  const TextNode(this.text, super.line);

  final String text;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    out.write(text);
  }
}

/// `{{ expr }}`, or `{{{ expr }}}` when [raw]
class OutputNode extends Node {
  const OutputNode(this.expr, super.line, {this.raw = false});

  final Expr expr;
  final bool raw;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    Object? value = ctx.eval(expr, scope, line);
    out.write(raw ? ctx.text(value) : ctx.escape(value));
  }
}

/// `@if`, `@elseif`, `@else` and `@unless`
class IfNode extends Node {
  const IfNode(this.branches, this.otherwise, super.line);

  final List<(Expr, List<Node>)> branches;
  final List<Node> otherwise;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    for ((Expr, List<Node>) branch in branches) {
      if (truthy(ctx.eval(branch.$1, scope, line), scope.stringZeroIsFalse)) {
        ctx.renderNodes(branch.$2, scope, out);
        return;
      }
    }
    ctx.renderNodes(otherwise, scope, out);
  }
}

/// `@each((item, index) in items)`, with `@else` for an empty list
class EachNode extends Node {
  const EachNode(
    this.item,
    this.key,
    this.iterable,
    this.body,
    this.otherwise,
    super.line,
  );

  final String item;

  /// the index for a list, the key for a map
  final String? key;
  final Expr iterable;
  final List<Node> body;
  final List<Node> otherwise;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    Object? value = ctx.eval(iterable, scope, line);
    List<(Object?, Object?)> entries = switch (value) {
      null => <(Object?, Object?)>[],
      Map<Object?, Object?> map => <(Object?, Object?)>[
        for (MapEntry<Object?, Object?> entry in map.entries)
          (entry.value, entry.key),
      ],
      Iterable<Object?> list => <(Object?, Object?)>[
        for (Object? item in list) (item, null),
      ],
      _ => throw ViewException(
        '@each needs a list or a map, not ${value.runtimeType}',
        template: ctx.template,
        line: line,
      ),
    };
    if (entries.isEmpty) {
      ctx.renderNodes(otherwise, scope, out);
      return;
    }
    Object? outer = scope.lookup(r'$loop');
    Loop? parent = outer is Loop ? outer : null;
    for (int i = 0; i < entries.length; i++) {
      (Object?, Object?) entry = entries[i];
      Scope inner = Scope(<String, Object?>{
        item: entry.$1,
        ?key: entry.$2 ?? i,
        r'$loop': Loop(i, entries.length, parent),
      }, scope);
      ctx.renderNodes(body, inner, out);
    }
  }
}

/// `$loop` in `@each`: a map that works out its values when they are
/// read, so a round of the loop builds no map.
class Loop extends UnmodifiableMapBase<String, Object?> {
  Loop(this.index, this.count, this.parent) : depth = (parent?.depth ?? 0) + 1;

  /// the round, from 0
  final int index;

  /// the number of rounds
  final int count;

  /// the `$loop` of the loop around this one, null for the outer loop
  final Loop? parent;

  /// 1 for the outer loop, 2 for a loop inside it
  final int depth;

  static const List<String> _keys = <String>[
    'index',
    'first',
    'last',
    'length',
    'iteration',
    'count',
    'remaining',
    'even',
    'odd',
    'depth',
    'parent',
  ];

  @override
  Iterable<String> get keys => _keys;

  @override
  Object? operator [](Object? key) => switch (key) {
    'index' => index,
    'first' => index == 0,
    'last' => index == count - 1,
    'length' || 'count' => count,
    'iteration' => index + 1,
    'remaining' => count - index - 1,
    // by `iteration`: the first round is odd
    'even' => index.isOdd,
    'odd' => index.isEven,
    'depth' => depth,
    'parent' => parent,
    _ => null,
  };
}

/// `@include('name')`, `@includeIf(condition, 'name')` and
/// `@includeWhen(condition, 'name')`. The template sees the variables of
/// the template that includes it, and the [data] on top of them.
class IncludeNode extends Node {
  const IncludeNode(this.name, this.condition, this.data, super.line);

  final Expr name;
  final Expr? condition;

  /// `@include('name', { title: 'Hi' })`: more variables for the template
  final Expr? data;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    Expr? condition = this.condition;
    if (condition != null &&
        !truthy(ctx.eval(condition, scope, line), scope.stringZeroIsFalse)) {
      return;
    }
    Object? template = ctx.eval(name, scope, line);
    if (template is! String) {
      throw ViewException(
        '@include needs a template name',
        template: ctx.template,
        line: line,
      );
    }
    Map<String, Object?> vars = <String, Object?>{};
    Expr? data = this.data;
    if (data != null) {
      Object? extra = ctx.eval(data, scope, line);
      if (extra is! Map<Object?, Object?>) {
        throw ViewException(
          'the data of @include must be a map, eg. '
          "@include('name', { title: 'Home' })",
          template: ctx.template,
          line: line,
        );
      }
      for (MapEntry<Object?, Object?> entry in extra.entries) {
        vars['${entry.key}'] = entry.value;
      }
    }
    ctx.renderTemplate(template, Scope(vars, scope), out, line);
  }
}

/// `@json(value)`: the value as JSON, see [SafeString.json]
class JsonNode extends Node {
  const JsonNode(this.expr, super.line);

  final Expr expr;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    Object? value = ctx.eval(expr, scope, line);
    try {
      out.write(SafeString.json(value).value);
    } on ViewException catch (error) {
      throw ViewException(
        '@json ${error.message}',
        template: ctx.template,
        line: line,
      );
    }
  }
}

/// `@error('email') ... @end`: the body shows when `errors` has a
/// message for the field. Inside it, `message` is the first message.
class ErrorNode extends Node {
  const ErrorNode(this.field, this.body, this.otherwise, super.line);

  final Expr field;
  final List<Node> body;
  final List<Node> otherwise;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    String name = stringify(ctx.eval(field, scope, line));
    String? message = _message(_find(scope.lookup('errors'), name));
    if (message == null) {
      ctx.renderNodes(otherwise, scope, out);
      return;
    }
    Scope inner = Scope(<String, Object?>{'message': message}, scope);
    ctx.renderNodes(body, inner, out);
  }

  /// the errors of [name]: the key `user.email` first, as the validator
  /// gives it, then `email` inside `user`
  static Object? _find(Object? errors, String name) {
    if (errors is! Map<Object?, Object?>) return null;
    if (errors.containsKey(name)) return errors[name];
    Object? at = errors;
    for (String part in name.split('.')) {
      if (at is! Map<Object?, Object?>) return null;
      at = at[part];
    }
    return at;
  }

  /// text is the message. A list gives its first item. Empty text, an
  /// empty list and any other value are no message.
  static String? _message(Object? value) {
    if (value is Iterable<Object?>) value = value.isEmpty ? null : value.first;
    if (value is SafeString) value = value.value;
    return value is String && value.isNotEmpty ? value : null;
  }
}

/// `@component('name', props) ... @end`. The component sees only its
/// props, `$props`, `$slots`, `$slot`, `$attributes`, the shared data
/// and the globals.
class ComponentNode extends Node {
  const ComponentNode(this.name, this.props, this.main, this.slots, super.line);

  final Expr name;
  final Expr? props;
  final List<Node> main;
  final Map<String, List<Node>> slots;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    Object? template = ctx.eval(name, scope, line);
    if (template is! String) {
      throw ViewException(
        '@component needs a template name',
        template: ctx.template,
        line: line,
      );
    }
    Expr? propsExpr = this.props;
    Object? props = propsExpr == null
        ? <String, Object?>{}
        : ctx.eval(propsExpr, scope, line);
    if (props is! Map<Object?, Object?>) {
      throw ViewException(
        'the props of a component must be a map',
        template: ctx.template,
        line: line,
      );
    }

    Map<String, Object?> rendered = <String, Object?>{};
    String content = _slot(ctx, main, scope);
    // like Blade's `$slot`, the main slot is always there: empty text
    // when it has only spaces
    rendered['main'] = SafeString(content.trim().isEmpty ? '' : content);
    for (MapEntry<String, List<Node>> slot in slots.entries) {
      rendered[slot.key] = SafeString(_slot(ctx, slot.value, scope));
    }

    Map<String, Object?> vars = <String, Object?>{
      for (MapEntry<Object?, Object?> prop in props.entries)
        '${prop.key}': prop.value,
    };
    Scope inner = Scope(<String, Object?>{
      ...vars,
      r'$props': props,
      r'$slots': rendered,
      r'$slot': rendered['main'],
      r'$attributes': Attributes(vars),
    }, ctx.shared);
    ctx.renderTemplate(template, inner, out, line);
  }

  /// a slot renders with the variables of the caller
  String _slot(RenderContext ctx, List<Node> nodes, Scope scope) {
    StringBuffer out = StringBuffer();
    ctx.renderNodes(nodes, Scope(<String, Object?>{}, scope), out);
    return out.toString();
  }
}

/// `@slot('name') ... @end`, only directly inside a component
class SlotNode extends Node {
  const SlotNode(this.name, this.body, super.line);

  final String name;
  final List<Node> body;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    throw ViewException(
      '@slot must be directly inside a component',
      template: ctx.template,
      line: line,
    );
  }
}

/// `@let(name = value)`, or `@assign(name = value)` when [assign]
class LetNode extends Node {
  const LetNode(this.name, this.value, super.line, {this.assign = false});

  final String name;
  final Expr value;
  final bool assign;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    Object? result = ctx.eval(value, scope, line);
    if (!assign) {
      scope.define(name, result);
      return;
    }
    try {
      scope.assign(name, result);
    } on ViewException catch (error) {
      throw ViewException(error.message, template: ctx.template, line: line);
    }
  }
}

/// `@class(['btn', { active: isActive }])`: `class="..."` with the
/// names whose value is true. The output is escaped.
class ClassNode extends Node {
  const ClassNode(this.expr, super.line);

  final Expr expr;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    List<String> names = <String>[];
    _add(names, ctx.eval(expr, scope, line), scope.stringZeroIsFalse);
    out.write('class="${escapeHtml(names.join(' '))}"');
  }

  /// text, a map of name to condition, or a list of these
  static void _add(List<String> names, Object? value, bool zeroIsFalse) {
    switch (value) {
      case String value:
        if (value.isNotEmpty) names.add(value);
      case Map<Object?, Object?> value:
        for (MapEntry<Object?, Object?> entry in value.entries) {
          if (truthy(entry.value, zeroIsFalse)) names.add('${entry.key}');
        }
      case Iterable<Object?> value:
        for (Object? item in value) {
          _add(names, item, zeroIsFalse);
        }
    }
  }
}

/// `@checked(x)`, `@selected(x)` and `@disabled(x)`: the attribute name
/// when x is true
class AttributeNode extends Node {
  const AttributeNode(this.name, this.expr, super.line);

  final String name;
  final Expr expr;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    if (truthy(ctx.eval(expr, scope, line), scope.stringZeroIsFalse)) {
      out.write(name);
    }
  }
}

/// `@once ... @end`: the body shows only the first time in one render,
/// eg. a `<script>` in a component that is used many times
class OnceNode extends Node {
  const OnceNode(this.key, this.body, super.line);

  /// the template and the number of the tag in it
  final String key;
  final List<Node> body;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    if (ctx.once.add(key)) ctx.renderNodes(body, scope, out);
  }
}

/// `@extends('layouts/app')`: the layout of the template. It prints
/// nothing: `RenderContext.renderTemplate` renders the layout.
class ExtendsNode extends Node {
  const ExtendsNode(this.name, super.line);

  final Expr name;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {}
}

/// `@section('name') ... @end`, or `@section('name', value)`: content
/// for the `@yield('name')` of the layout. The first one with a name
/// wins, so a page wins over its layout.
class SectionNode extends Node {
  const SectionNode(this.name, this.body, this.value, super.line);

  final String name;
  final List<Node> body;

  /// the short form. It is escaped, like `{{ }}`.
  final Expr? value;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    if (ctx.sections.containsKey(name)) return;
    Expr? value = this.value;
    ctx.sections[name] = value == null
        ? ctx.capture(body, Scope(<String, Object?>{}, scope))
        : ctx.escape(ctx.eval(value, scope, line));
  }
}

/// `@yield('name')` or `@yield('name', fallback)`: prints a section
class YieldNode extends Node {
  const YieldNode(this.name, this.fallback, super.line);

  final String name;

  /// printed when there is no such section. It is escaped, like `{{ }}`.
  final Expr? fallback;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    String? content = ctx.sections[name];
    Expr? fallback = this.fallback;
    if (content != null) {
      out.write(content);
    } else if (fallback != null) {
      out.write(ctx.escape(ctx.eval(fallback, scope, line)));
    }
  }
}

/// `@stack('name')`: prints every `@push('name')` of the render
class StackNode extends Node {
  const StackNode(this.name, super.line);

  final String name;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    out.write(ctx.stackMark(name));
  }
}

/// `@push('name') ... @end` adds to the end of a stack. `@prepend` adds
/// to the start.
class PushNode extends Node {
  const PushNode(this.name, this.body, super.line, {this.prepend = false});

  final String name;
  final List<Node> body;
  final bool prepend;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    String content = ctx.capture(body, Scope(<String, Object?>{}, scope));
    List<String> stack = ctx.stacks[name] ??= <String>[];
    stack.insert(prepend ? 0 : stack.length, content);
  }
}

/// `@csrf`: the hidden `_token` field for `CsrfMiddleware`. The token
/// is `csrfToken` of the shared data: `view()` sets it with a session.
class CsrfNode extends Node {
  const CsrfNode(super.line);

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    // the shared data, so the view data can not change the token
    Object? token = ctx.shared.lookup('csrfToken');
    if (token is Function) {
      try {
        token = Function.apply(token, const <Object?>[]);
      } on Object catch (error) {
        throw ViewException(
          '@csrf could not read the token: $error',
          template: ctx.template,
          line: line,
        );
      }
    }
    if (token is! String || token.isEmpty) {
      throw ViewException(
        '@csrf needs a session. Add SessionMiddleware to the route.',
        template: ctx.template,
        line: line,
      );
    }
    out.write(
      '<input type="hidden" name="_token" value="${escapeHtml(token)}">',
    );
  }
}

/// `@method('PUT')`: the hidden `_method` field for `MethodOverride`
class MethodNode extends Node {
  const MethodNode(this.method, super.line);

  final Expr method;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    String value = escapeHtml(ctx.text(ctx.eval(method, scope, line)));
    out.write('<input type="hidden" name="_method" value="$value">');
  }
}
