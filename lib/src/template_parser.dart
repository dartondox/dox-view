import 'expression.dart';
import 'lexer.dart';
import 'nodes.dart';
import 'view_directive.dart';
import 'view_engine.dart';
import 'view_exception.dart';

/// the tags of the engine. Any other `@name(...)` is a component when
/// `components/name` exists, or else plain text.
const Set<String> _tags = <String>{
  'if',
  'elseif',
  'else',
  'unless',
  'each',
  'end',
  'include',
  'includeIf',
  'component',
  'slot',
  'let',
  'assign',
};

/// tags like Blade. A component with the same name wins. With no `( )`,
/// the ones in [_argDirectives] stay plain text, as before they were tags.
/// The ones in [_blockDirectives] are tags only alone on their line, so
/// text like `@once upon a time` stays text.
const Set<String> _argDirectives = <String>{
  'isset',
  'empty',
  'env',
  'class',
  'checked',
  'selected',
  'disabled',
  'extends',
  'section',
  'yield',
  'stack',
  'push',
  'prepend',
  'method',
  'includeWhen',
  'json',
  'error',
};

/// the ones of [_argDirectives] that are a tag with a space before `(`
/// only when the first argument is text in quotes. So prose like
/// `git @push (force)` or `the @yield (curve)` stays text.
const Set<String> _quotedDirectives = <String>{
  'extends',
  'section',
  'yield',
  'stack',
  'push',
  'prepend',
  'method',
  'error',
};

/// the ones of [_argDirectives] that are a tag only with the `(` right
/// after the name. So prose like `the @json (format)` stays text.
const Set<String> _tightDirectives = <String>{'includeWhen', 'json'};

const String _useEnd = 'Use "@end".';

/// the Blade names that are not Dox tags, and what to write in Dox.
/// They stay text; the parser only warns.
const Map<String, String> _bladeNames = <String, String>{
  'foreach': 'Use "@each(item in items) ... @end".',
  'forelse': 'Use "@each(item in items) ... @else ... @end".',
  'for': 'Use "@each(item in items) ... @end".',
  'while': 'Dox has no "@while". Use "@each(item in items) ... @end".',
  'switch': 'Use "@if(...) ... @elseif(...) ... @else ... @end".',
  'php': 'Dox has no "@php". Use "@let(name = value)".',
  'endphp': 'Dox has no "@php". Use "@let(name = value)".',
  'show': 'Use "@end", then "@yield(\'name\')" to print the section.',
  'parent':
      'Dox has no "@parent". The section of the page replaces the '
      'section of the layout. Use "@stack" and "@push" to add content.',
  'endforeach': _useEnd,
  'endforelse': _useEnd,
  'endfor': _useEnd,
  'endwhile': _useEnd,
  'endswitch': _useEnd,
  'endif': _useEnd,
  'endunless': _useEnd,
  'endisset': _useEnd,
  'endempty': _useEnd,
  'endauth': _useEnd,
  'endguest': _useEnd,
  'endenv': _useEnd,
  'endproduction': _useEnd,
  'endonce': _useEnd,
  'endverbatim': _useEnd,
  'endsection': _useEnd,
  'stop': _useEnd,
  'endpush': _useEnd,
  'endprepend': _useEnd,
  'endcomponent': _useEnd,
  'endslot': _useEnd,
  'enderror': _useEnd,
};

/// the ones of [_argDirectives] that can take two arguments
const Set<String> _twoArgDirectives = <String>{'section', 'yield'};

/// the ones of [_argDirectives] with a body and an `@end`
/// `@section` has no body with two arguments: see [TemplateParser._hasBody].
const Set<String> _endDirectives = <String>{
  'isset',
  'empty',
  'env',
  'section',
  'push',
  'prepend',
  'error',
};
const Set<String> _blockDirectives = <String>{
  'auth',
  'guest',
  'production',
  'verbatim',
  'once',
  'csrf',
};

final RegExp _eachHeader = RegExp(
  r'^\s*(?:\(\s*([A-Za-z_$][\w$]*)\s*(?:,\s*([A-Za-z_$][\w$]*)\s*)?\)|([A-Za-z_$][\w$]*))\s+in\s+([\s\S]+)$',
);
final RegExp _letHeader = RegExp(r'^\s*([A-Za-z_$][\w$]*)\s*=([\s\S]+)$');
// the rest of the line after a tag: spaces and the line break, or
// spaces up to the end of the file
final RegExp _lineStart = RegExp(r'^[ \t]*(?:\r?\n|$)');
final RegExp _lineEnd = RegExp(r'[ \t]*$');

/// Turns the tokens of a template into nodes.
class TemplateParser {
  TemplateParser(String name, String source, ViewEngine engine)
    : this._(name, engine, Lexer(source, name));

  TemplateParser._(this.name, this.engine, Lexer lexer)
    : _tokens = lexer.tokenize(),
      _bladeRawLines = lexer.bladeRawLines;

  final String name;
  final ViewEngine engine;
  final List<Token> _tokens;
  final List<int> _bladeRawLines;
  int _pos = 0;

  /// the number of `@once` tags so far: each one has its own key
  int _once = 0;

  /// the `@extends` of the template
  ExtendsNode? _layout;

  /// the number of open blocks around the token that [_body] reads now
  int _depth = 0;

  /// see [_endScores]
  List<int>? _scores;

  /// true for the name of a tag of the engine. A directive of the app
  /// can not use it.
  static bool isBuiltIn(String name) =>
      _tags.contains(name) ||
      _argDirectives.contains(name) ||
      _blockDirectives.contains(name);

  Template parse() {
    for (int line in _bladeRawLines) {
      engine.warn(
        '$name:$line "{!! !!}" is not Dox syntax. Use "{{{ value }}}".',
      );
    }
    List<Node> nodes = _body(const <String>{}, null).$1;
    return Template(name, nodes, _layout);
  }

  /// nodes up to one of the tags in [stops]. Gives the nodes and the
  /// stop tag.
  (List<Node>, Token?) _body(Set<String> stops, Token? opener) {
    List<Node> nodes = <Node>[];
    int depth = _depth;
    if (opener != null) _depth++;
    while (_pos < _tokens.length) {
      Token token = _tokens[_pos++];
      switch (token.kind) {
        case TokenKind.text:
          nodes.add(TextNode(token.value, token.line));
        case TokenKind.output:
          nodes.add(OutputNode(_expr(token.value, token), token.line));
        case TokenKind.rawOutput:
          nodes.add(
            OutputNode(_expr(token.value, token), token.line, raw: true),
          );
        case TokenKind.tag:
          String? component = _component(token);
          if (component == null && !_isTag(token, _pos - 1, _depth)) {
            // eg. `@media` in CSS
            _warnBlade(token);
            nodes.add(TextNode(token.value, token.line));
            continue;
          }
          if (token.standalone) _trimLine(nodes);
          if (stops.contains(token.name)) {
            _depth = depth;
            return (nodes, token);
          }
          nodes.add(_tag(token, component));
      }
    }
    if (opener != null) throw _error('@${opener.name} has no @end', opener);
    return (nodes, null);
  }

  /// warn when the text [token] is a Blade name in the place of a tag:
  /// with `(` right after the name, alone on its line, or an `@end...`
  /// name. So prose like
  /// `the @foreach loop` or `ask your @parent (or guardian)` is quiet.
  /// It warns as soon as it sees the name, so the warning also comes
  /// before a parse error like `@if has no @end`.
  void _warnBlade(Token token) {
    String? hint = _bladeNames[token.name];
    if (hint == null || token.selfClosing) return;
    if (engine.directiveFor(token.name) != null) return;
    bool tight = token.args != null && !_spaceBeforeArgs(token);
    // `@endif` and the like are not words, so they warn anywhere
    bool closer = token.name.startsWith('end');
    if (!tight && !token.standalone && !closer) return;
    engine.warn('$name:${token.line} "@${token.name}" is not a Dox tag. $hint');
  }

  /// [index] is the place of [token] in the tokens. [depth] is the
  /// number of open blocks around it.
  bool _isTag(Token token, int index, int depth) {
    if (_tags.contains(token.name)) return true;
    if (_blockDirectives.contains(token.name)) return token.standalone;
    bool custom = engine.directiveFor(token.name) != null;
    if (!custom && !_argDirectives.contains(token.name)) return false;
    if (token.args == null) return false;
    // text like `@empty (none)` or `@class (see docs)`: with a space
    // before `(`, in the middle of a line, it is a tag only when its args
    // parse. A tag with a body, like `@isset` or `@push`, also needs its
    // own `@end` after it, on any line.
    // The layout, stack and `@method` tags also need text in quotes as
    // the first arg, on any line: `git @push (force)` stays text.
    if (!_spaceBeforeArgs(token)) return true;
    if (_tightDirectives.contains(token.name)) return false;
    if (_quotedDirectives.contains(token.name) && !_quotedFirstArg(token)) {
      return false;
    }
    bool needsEnd = _hasBody(token);
    if (token.standalone) return !needsEnd || _hasEnd(index + 1, depth);
    int? count = _argCount(token);
    if (count == null) return false;
    if (custom) return true;
    if (count != 1 && !(count == 2 && _twoArgDirectives.contains(token.name))) {
      return false;
    }
    return !needsEnd || _hasEnd(index + 1, depth);
  }

  /// the number of args of [token], null when they do not parse
  int? _argCount(Token token) => _argList(token)?.length;

  /// the args of [token], null when they do not parse
  List<Expr>? _argList(Token token) {
    try {
      return ExprParser(token.args ?? '').parseList();
    } on ViewException {
      return null;
    }
  }

  /// true when the first arg of [token] is text in quotes, like `'title'`
  bool _quotedFirstArg(Token token) {
    List<Expr>? args = _argList(token);
    if (args == null || args.isEmpty) return false;
    Expr first = args[0];
    return first is LiteralExpr && first.value is String;
  }

  /// true for a directive that has a body and an `@end`.
  /// `@section('title', 'Home')` has no body.
  bool _hasBody(Token token) =>
      _endDirectives.contains(token.name) &&
      !(token.name == 'section' && _argCount(token) == 2);

  /// true when an `@end` after [from] closes the block that starts just
  /// before it, and more `@end` tags follow for the [depth] blocks around
  /// it. The blocks in between are counted.
  bool _hasEnd(int from, int depth) => _endScores()[from] > depth;

  /// for each place in the tokens: the most `@end` tags, less the blocks
  /// that open, from that place up to some later place. So `@end @end`
  /// is 2, and `@if(x) @end @end` is 1.
  /// It is done once, from the last token back. Before, each tag with a
  /// space before `(` scanned all the tags after it, again and again for
  /// tags inside it, so a deep template took very long.
  /// A tag here does not know the blocks around it. This only adds
  /// blocks, so a tag never finds an `@end` that is not there.
  List<int> _endScores() {
    List<int>? scores = _scores;
    if (scores != null) return scores;
    // set it first: _opensBlock reads the places after i
    scores = _scores = List<int>.filled(_tokens.length + 1, 0);
    for (int i = _tokens.length - 1; i >= 0; i--) {
      Token token = _tokens[i];
      int step = 0;
      if (token.kind == TokenKind.tag) {
        if (token.name == 'end') {
          step = 1;
        } else if (_opensBlock(token, i)) {
          step = -1;
        }
      }
      int score = step + scores[i + 1];
      scores[i] = score < 0 ? 0 : score;
    }
    return scores;
  }

  /// true for a tag that needs its own `@end`
  bool _opensBlock(Token token, int index) {
    if (_component(token) != null) return !token.selfClosing;
    if (!_isTag(token, index, 0)) return false;
    if (engine.directiveFor(token.name) != null) return false;
    return switch (token.name) {
      'else' || 'elseif' || 'include' || 'includeIf' => false,
      'let' || 'assign' || 'class' || 'checked' => false,
      'selected' || 'disabled' => false,
      'extends' || 'yield' || 'stack' || 'method' || 'csrf' => false,
      'includeWhen' || 'json' => false,
      'section' => _hasBody(token),
      'component' => !token.selfClosing,
      _ => true,
    };
  }

  /// `@name (...)`, not `@name(...)`
  bool _spaceBeforeArgs(Token token) {
    int at = (token.selfClosing ? 2 : 1) + token.name.length;
    return token.value.codeUnitAt(at) != 0x28; // (
  }

  Node _tag(Token token, String? component) {
    if (component != null) {
      List<Expr> args = _args(token, 0, 1);
      return _componentNode(
        token,
        LiteralExpr(component),
        args.isEmpty ? null : args[0],
      );
    }
    ViewDirective? directive = engine.directiveFor(token.name);
    if (directive != null) {
      Expr call = DirectiveExpr(directive, _args(token, 0, 1 << 30));
      return OutputNode(call, token.line);
    }
    switch (token.name) {
      case 'extends':
        return _extends(token);
      case 'section':
        List<Expr> args = _args(token, 1, 2);
        String section = _name(token, args[0]);
        if (args.length == 2) {
          return SectionNode(section, const <Node>[], args[1], token.line);
        }
        List<Node> body = _body(const <String>{'end'}, token).$1;
        return SectionNode(section, body, null, token.line);
      case 'yield':
        List<Expr> args = _args(token, 1, 2);
        return YieldNode(
          _name(token, args[0]),
          args.length > 1 ? args[1] : null,
          token.line,
        );
      case 'stack':
        return StackNode(_name(token, _args(token, 1)[0]), token.line);
      case 'push':
      case 'prepend':
        String stack = _name(token, _args(token, 1)[0]);
        List<Node> body = _body(const <String>{'end'}, token).$1;
        return PushNode(
          stack,
          body,
          token.line,
          prepend: token.name == 'prepend',
        );
      case 'csrf':
        if (token.args != null) throw _error('@csrf takes no arguments', token);
        return CsrfNode(token.line);
      case 'method':
        return MethodNode(_args(token, 1)[0], token.line);
      case 'if':
        return _if(token, _expr(_rawArgs(token), token));
      case 'unless':
        return _if(token, UnaryExpr('!', _expr(_rawArgs(token), token)));
      case 'isset':
        return _if(token, IssetExpr(_expr(_rawArgs(token), token)));
      case 'empty':
        Expr value = IssetExpr(_expr(_rawArgs(token), token), value: true);
        return _if(token, UnaryExpr('!', value));
      case 'auth':
      case 'guest':
        if (token.args != null) {
          throw _error('@${token.name} takes no arguments', token);
        }
        // `view()` sets `$auth` from `req.auth`. The view data can not
        // hide it.
        Expr loggedIn = const OuterExpr(r'$auth');
        return _if(
          token,
          token.name == 'auth' ? loggedIn : UnaryExpr('!', loggedIn),
        );
      case 'env':
        return _if(token, EnvExpr(_args(token, 1)[0], engine.environment));
      case 'production':
        return _if(
          token,
          LiteralExpr(engine.environment.toLowerCase() == 'production'),
        );
      case 'class':
        return ClassNode(_args(token, 1)[0], token.line);
      case 'checked':
      case 'selected':
      case 'disabled':
        return AttributeNode(token.name, _args(token, 1)[0], token.line);
      case 'verbatim':
        List<Node> text = _body(const <String>{'end'}, token).$1;
        return IfNode(
          <(Expr, List<Node>)>[(const LiteralExpr(true), text)],
          <Node>[],
          token.line,
        );
      case 'once':
        List<Node> body = _body(const <String>{'end'}, token).$1;
        return OnceNode('$name#${_once++}', body, token.line);
      case 'each':
        return _each(token);
      case 'include':
        List<Expr> args = _args(token, 1, 2);
        return IncludeNode(
          args[0],
          null,
          args.length > 1 ? args[1] : null,
          token.line,
        );
      case 'includeIf':
      case 'includeWhen':
        List<Expr> args = _args(token, 2, 3);
        return IncludeNode(
          args[1],
          args[0],
          args.length > 2 ? args[2] : null,
          token.line,
        );
      case 'json':
        return JsonNode(_args(token, 1)[0], token.line);
      case 'error':
        Expr field = _args(token, 1)[0];
        (List<Node>, Token?) body = _body(const <String>{'else', 'end'}, token);
        List<Node> otherwise = body.$2!.name == 'else'
            ? _body(const <String>{'end'}, token).$1
            : <Node>[];
        return ErrorNode(field, body.$1, otherwise, token.line);
      case 'component':
        List<Expr> args = _args(token, 1, 2);
        return _componentNode(token, args[0], args.length > 1 ? args[1] : null);
      case 'slot':
        return _slot(token);
      case 'let':
      case 'assign':
        RegExpMatch? match = _letHeader.firstMatch(_rawArgs(token));
        if (match == null) {
          throw _error('use @${token.name}(name = value)', token);
        }
        return LetNode(
          match[1]!,
          _expr(match[2]!, token),
          token.line,
          assign: token.name == 'assign',
        );
      case 'else':
      case 'elseif':
      case 'end':
        throw _error('@${token.name} has no matching tag before it', token);
    }
    throw StateError('unknown tag @${token.name}');
  }

  /// `@if` and the tags like it. Only `@if` has `@elseif`.
  Node _if(Token token, Expr condition) {
    List<(Expr, List<Node>)> branches = <(Expr, List<Node>)>[];
    Set<String> stops = token.name == 'if'
        ? const <String>{'elseif', 'else', 'end'}
        : const <String>{'else', 'end'};
    while (true) {
      (List<Node>, Token?) body = _body(stops, token);
      branches.add((condition, body.$1));
      Token stop = body.$2!;
      if (stop.name == 'end') return IfNode(branches, <Node>[], token.line);
      if (stop.name == 'else') {
        List<Node> otherwise = _body(const <String>{'end'}, token).$1;
        return IfNode(branches, otherwise, token.line);
      }
      condition = _expr(_rawArgs(stop), stop);
    }
  }

  Node _each(Token token) {
    RegExpMatch? match = _eachHeader.firstMatch(_rawArgs(token));
    if (match == null) {
      throw _error(
        'use @each(item in items) or @each((item, i) in items)',
        token,
      );
    }
    Expr iterable = _expr(match[4]!, token);
    (List<Node>, Token?) body = _body(const <String>{'else', 'end'}, token);
    List<Node> otherwise = body.$2!.name == 'else'
        ? _body(const <String>{'end'}, token).$1
        : <Node>[];
    return EachNode(
      match[1] ?? match[3]!,
      match[2],
      iterable,
      body.$1,
      otherwise,
      token.line,
    );
  }

  Node _componentNode(Token token, Expr name, Expr? props) {
    if (token.selfClosing) {
      return ComponentNode(
        name,
        props,
        <Node>[],
        <String, List<Node>>{},
        token.line,
      );
    }
    List<Node> main = <Node>[];
    Map<String, List<Node>> slots = <String, List<Node>>{};
    for (Node node in _body(const <String>{'end'}, token).$1) {
      if (node is SlotNode) {
        slots[node.name] = node.body;
      } else {
        main.add(node);
      }
    }
    return ComponentNode(name, props, main, slots, token.line);
  }

  Node _slot(Token token) {
    String name = _name(token, _args(token, 1)[0]);
    List<Node> body = _body(const <String>{'end'}, token).$1;
    return SlotNode(name, body, token.line);
  }

  /// the name of a slot, a section or a stack: it must be a string
  String _name(Token token, Expr name) {
    if (name is! LiteralExpr || name.value is! String) {
      throw _error(
        'the ${token.name} name must be a string, '
        "eg. @${token.name}('title')",
        token,
      );
    }
    return name.value! as String;
  }

  /// `@extends('layouts/app')`: once, before any other content
  Node _extends(Token token) {
    if (_layout != null) {
      throw _error('a template can have only one @extends', token);
    }
    for (int i = 0; i < _pos - 1; i++) {
      Token before = _tokens[i];
      if (before.kind != TokenKind.text || before.value.trim().isNotEmpty) {
        throw _error('@extends must be the first thing in a template', token);
      }
    }
    return _layout = ExtendsNode(_args(token, 1)[0], token.line);
  }

  /// the template path of a component tag like `@button(...)` or
  /// `@form.input(...)`, null when it is not a component
  String? _component(Token token) {
    if (_tags.contains(token.name) || token.args == null) return null;
    String path = 'components/${token.name.replaceAll('.', '/')}';
    return engine.exists(path) ? path : null;
  }

  /// a tag alone on its line leaves no empty line: remove the spaces
  /// before it, and the line break after it
  void _trimLine(List<Node> nodes) {
    if (nodes.isNotEmpty && nodes.last is TextNode) {
      TextNode last = nodes.removeLast() as TextNode;
      String text = last.text.replaceFirst(_lineEnd, '');
      if (text.isNotEmpty) nodes.add(TextNode(text, last.line));
    }
    if (_pos < _tokens.length && _tokens[_pos].kind == TokenKind.text) {
      Token next = _tokens[_pos];
      next.value = next.value.replaceFirst(_lineStart, '');
    }
  }

  String _rawArgs(Token token) {
    String? args = token.args;
    if (args == null || args.trim().isEmpty) {
      throw _error('@${token.name} needs ( )', token);
    }
    return args;
  }

  /// the args of [token], between [min] and [max] of them
  List<Expr> _args(Token token, int min, [int? max]) {
    max ??= min;
    List<Expr> args;
    try {
      args = token.args == null
          ? <Expr>[]
          : ExprParser(token.args!).parseList();
    } on ViewException catch (error) {
      throw _error(error.message, token);
    }
    if (args.length < min || args.length > max) {
      String count = min == max ? '$min' : '$min to $max';
      throw _error('@${token.name} needs $count arguments', token);
    }
    return args;
  }

  Expr _expr(String source, Token token) {
    try {
      return ExprParser(source).parse();
    } on ViewException catch (error) {
      throw _error(error.message, token);
    }
  }

  ViewException _error(String message, Token token) =>
      ViewException(message, template: name, line: token.line);
}
