import 'expression.dart';
import 'safe_string.dart';
import 'scope.dart';
import 'view_engine.dart';
import 'view_exception.dart';

/// A parsed template.
class Template {
  const Template(this.name, this.nodes);

  final String name;
  final List<Node> nodes;
}

/// The state of one render.
class RenderContext {
  RenderContext(this.engine);

  final ViewEngine engine;

  /// the template that renders now, for error messages
  String template = '';
  int _depth = 0;

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
        'Does a template include itself?',
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
      renderNodes(found.nodes, scope, out);
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
    if (raw || value is SafeString) {
      out.write(stringify(value));
    } else {
      out.write(escapeHtml(stringify(value)));
    }
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
      if (truthy(ctx.eval(branch.$1, scope, line))) {
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
    for (int i = 0; i < entries.length; i++) {
      (Object?, Object?) entry = entries[i];
      Scope inner = Scope(<String, Object?>{
        item: entry.$1,
        ?key: entry.$2 ?? i,
        r'$loop': <String, Object?>{
          'index': i,
          'first': i == 0,
          'last': i == entries.length - 1,
          'length': entries.length,
        },
      }, scope);
      ctx.renderNodes(body, inner, out);
    }
  }
}

/// `@include('name')` and `@includeIf(condition, 'name')`. The template
/// sees the variables of the template that includes it.
class IncludeNode extends Node {
  const IncludeNode(this.name, this.condition, super.line);

  final Expr name;
  final Expr? condition;

  @override
  void render(RenderContext ctx, Scope scope, StringBuffer out) {
    Expr? condition = this.condition;
    if (condition != null && !truthy(ctx.eval(condition, scope, line))) {
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
    ctx.renderTemplate(template, Scope(<String, Object?>{}, scope), out, line);
  }
}

/// `@component('name', props) ... @end`. The component sees only its
/// props, `$props`, `$slots` and the globals.
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
    if (content.trim().isNotEmpty) rendered['main'] = SafeString(content);
    for (MapEntry<String, List<Node>> slot in slots.entries) {
      rendered[slot.key] = SafeString(_slot(ctx, slot.value, scope));
    }

    Scope inner = Scope(<String, Object?>{
      for (MapEntry<Object?, Object?> prop in props.entries)
        '${prop.key}': prop.value,
      r'$props': props,
      r'$slots': rendered,
    }, ctx.engine.globals);
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
