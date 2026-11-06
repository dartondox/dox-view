import 'expression.dart';
import 'lexer.dart';
import 'nodes.dart';
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
const Set<String> _argDirectives = <String>{
  'isset',
  'empty',
  'env',
  'class',
  'checked',
  'selected',
  'disabled',
};
const Set<String> _blockDirectives = <String>{
  'auth',
  'guest',
  'production',
  'verbatim',
  'once',
};

final RegExp _eachHeader = RegExp(
  r'^\s*(?:\(\s*([A-Za-z_$][\w$]*)\s*(?:,\s*([A-Za-z_$][\w$]*)\s*)?\)|([A-Za-z_$][\w$]*))\s+in\s+([\s\S]+)$',
);
final RegExp _letHeader = RegExp(r'^\s*([A-Za-z_$][\w$]*)\s*=([\s\S]+)$');
final RegExp _lineStart = RegExp(r'^[ \t]*\r?\n');
final RegExp _lineEnd = RegExp(r'[ \t]*$');

/// Turns the tokens of a template into nodes.
class TemplateParser {
  TemplateParser(this.name, String source, this.engine)
    : _tokens = Lexer(source, name).tokenize();

  final String name;
  final ViewEngine engine;
  final List<Token> _tokens;
  int _pos = 0;

  /// the number of `@once` tags so far: each one has its own key
  int _once = 0;

  List<Node> parse() => _body(const <String>{}, null).$1;

  /// nodes up to one of the tags in [stops]. Gives the nodes and the
  /// stop tag.
  (List<Node>, Token?) _body(Set<String> stops, Token? opener) {
    List<Node> nodes = <Node>[];
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
          if (component == null && !_isTag(token)) {
            // eg. `@media` in CSS
            nodes.add(TextNode(token.value, token.line));
            continue;
          }
          if (token.standalone) _trimLine(nodes);
          if (stops.contains(token.name)) return (nodes, token);
          nodes.add(_tag(token, component));
      }
    }
    if (opener != null) throw _error('@${opener.name} has no @end', opener);
    return (nodes, null);
  }

  bool _isTag(Token token) =>
      _tags.contains(token.name) ||
      _blockDirectives.contains(token.name) ||
      (_argDirectives.contains(token.name) && token.args != null);

  Node _tag(Token token, String? component) {
    if (component != null) {
      List<Expr> args = _args(token, 0, 1);
      return _componentNode(
        token,
        LiteralExpr(component),
        args.isEmpty ? null : args[0],
      );
    }
    switch (token.name) {
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
        // `view()` sets `$auth` from `req.auth`
        Expr loggedIn = const VariableExpr(r'$auth');
        return _if(
          token,
          token.name == 'auth' ? loggedIn : UnaryExpr('!', loggedIn),
        );
      case 'env':
        return _if(token, EnvExpr(_args(token, 1)[0], engine.environment));
      case 'production':
        return _if(token, LiteralExpr(engine.environment == 'production'));
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
        List<Expr> args = _args(token, 1);
        return IncludeNode(args[0], null, token.line);
      case 'includeIf':
        List<Expr> args = _args(token, 2);
        return IncludeNode(args[1], args[0], token.line);
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
    Expr name = _args(token, 1)[0];
    if (name is! LiteralExpr || name.value is! String) {
      throw _error("the slot name must be a string, eg. @slot('title')", token);
    }
    List<Node> body = _body(const <String>{'end'}, token).$1;
    return SlotNode(name.value! as String, body, token.line);
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
