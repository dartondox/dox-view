import 'safe_string.dart';
import 'scope.dart';
import 'view_exception.dart';

/// An expression in `{{ }}` or in the `()` of a tag.
abstract class Expr {
  const Expr();

  Object? evaluate(Scope scope);
}

class LiteralExpr extends Expr {
  const LiteralExpr(this.value);

  final Object? value;

  @override
  Object? evaluate(Scope scope) => value;
}

class ListExpr extends Expr {
  const ListExpr(this.items);

  final List<Expr> items;

  @override
  Object? evaluate(Scope scope) => <Object?>[
    for (Expr item in items) item.evaluate(scope),
  ];
}

class MapExpr extends Expr {
  const MapExpr(this.entries);

  final Map<String, Expr> entries;

  @override
  Object? evaluate(Scope scope) => <String, Object?>{
    for (MapEntry<String, Expr> entry in entries.entries)
      entry.key: entry.value.evaluate(scope),
  };
}

class VariableExpr extends Expr {
  const VariableExpr(this.name);

  final String name;

  @override
  Object? evaluate(Scope scope) => scope.lookup(name);
}

/// `a.b` or `a?.b`
class MemberExpr extends Expr {
  const MemberExpr(this.object, this.name, {this.optional = false});

  final Expr object;
  final String name;
  final bool optional;

  @override
  Object? evaluate(Scope scope) {
    Object? target = object.evaluate(scope);
    if (target == null && optional) return null;
    return readProperty(target, name);
  }
}

/// `a[b]`
class IndexExpr extends Expr {
  const IndexExpr(this.object, this.index);

  final Expr object;
  final Expr index;

  @override
  Object? evaluate(Scope scope) {
    Object? target = object.evaluate(scope);
    Object? key = index.evaluate(scope);
    if (target is List && key is int) {
      return key >= 0 && key < target.length ? target[key] : null;
    }
    if (key is String) return readProperty(target, key);
    throw ViewException('can not read [$key] of ${_type(target)}');
  }
}

/// `f(a, b)` or `a.method(b)`
class CallExpr extends Expr {
  const CallExpr(this.callee, this.args);

  final Expr callee;
  final List<Expr> args;

  @override
  Object? evaluate(Scope scope) {
    Expr callee = this.callee;
    if (callee is MemberExpr) {
      Object? target = callee.object.evaluate(scope);
      if (target == null && callee.optional) return null;
      return callMethod(target, callee.name, _args(scope));
    }
    Object? function = callee.evaluate(scope);
    if (function is! Function) {
      throw ViewException('${_describe(callee)} is not a function');
    }
    return Function.apply(function, _args(scope));
  }

  List<Object?> _args(Scope scope) => <Object?>[
    for (Expr arg in args) arg.evaluate(scope),
  ];
}

class UnaryExpr extends Expr {
  const UnaryExpr(this.op, this.operand);

  final String op;
  final Expr operand;

  @override
  Object? evaluate(Scope scope) {
    Object? value = operand.evaluate(scope);
    if (op == '!') return !truthy(value);
    if (value is num) return -value;
    throw ViewException('can not use - on ${_type(value)}');
  }
}

class BinaryExpr extends Expr {
  const BinaryExpr(this.op, this.left, this.right);

  final String op;
  final Expr left;
  final Expr right;

  @override
  Object? evaluate(Scope scope) {
    Object? a = left.evaluate(scope);
    switch (op) {
      case '&&':
        return truthy(a) ? right.evaluate(scope) : a;
      case '||':
        return truthy(a) ? a : right.evaluate(scope);
      case '??':
        return a ?? right.evaluate(scope);
    }
    Object? b = right.evaluate(scope);
    switch (op) {
      case '==':
      case '===':
        return a == b;
      case '!=':
      case '!==':
        return a != b;
      case '+':
        if (a is num && b is num) return a + b;
        if (a is String || b is String) return stringify(a) + stringify(b);
    }
    if (op == '<' || op == '<=' || op == '>' || op == '>=') {
      if (a is! Comparable<Object?> || b is! Comparable<Object?>) {
        throw ViewException('can not compare ${_type(a)} and ${_type(b)}');
      }
      int order = a.compareTo(b);
      return switch (op) {
        '<' => order < 0,
        '<=' => order <= 0,
        '>' => order > 0,
        _ => order >= 0,
      };
    }
    if (a is! num || b is! num) {
      throw ViewException('can not use $op on ${_type(a)} and ${_type(b)}');
    }
    return switch (op) {
      '-' => a - b,
      '*' => a * b,
      '/' => a / b,
      '%' => a % b,
      _ => a ~/ b,
    };
  }
}

/// `a ? b : c`
class ConditionalExpr extends Expr {
  const ConditionalExpr(this.condition, this.then, this.otherwise);

  final Expr condition;
  final Expr then;
  final Expr otherwise;

  @override
  Object? evaluate(Scope scope) => truthy(condition.evaluate(scope))
      ? then.evaluate(scope)
      : otherwise.evaluate(scope);
}

/// false for null, false, 0, '' and an empty list or map
bool truthy(Object? value) => switch (value) {
  null => false,
  bool value => value,
  num value => value != 0,
  String value => value.isNotEmpty,
  Iterable<Object?> value => value.isNotEmpty,
  Map<Object?, Object?> value => value.isNotEmpty,
  _ => true,
};

/// the text of [value] for the output: null is empty
String stringify(Object? value) => switch (value) {
  null => '',
  String value => value,
  SafeString value => value.value,
  _ => value.toString(),
};

/// `toJson()` of objects, made once per object
final Expando<Map<Object?, Object?>> _json = Expando<Map<Object?, Object?>>();

/// [target] as a map: a map, or an object with `toJson()`
Map<Object?, Object?>? _asMap(Object? target) {
  if (target is Map<Object?, Object?>) return target;
  if (target == null ||
      target is num ||
      target is String ||
      target is bool ||
      target is Iterable<Object?> ||
      target is Record) {
    return null;
  }
  Map<Object?, Object?>? cached = _json[target];
  if (cached != null) return cached;
  Object? json;
  try {
    json = (target as dynamic).toJson();
  } on NoSuchMethodError {
    return null;
  }
  if (json is! Map<Object?, Object?>) return null;
  return _json[target] = json;
}

/// `target.name`
Object? readProperty(Object? target, String name) {
  Map<Object?, Object?>? map = _asMap(target);
  if (map != null) {
    if (map.containsKey(name)) return map[name];
    return switch (name) {
      'length' => map.length,
      'isEmpty' => map.isEmpty,
      'isNotEmpty' => map.isNotEmpty,
      'keys' => map.keys.toList(),
      'values' => map.values.toList(),
      _ => null,
    };
  }
  switch (target) {
    case String target:
      switch (name) {
        case 'length':
          return target.length;
        case 'isEmpty':
          return target.isEmpty;
        case 'isNotEmpty':
          return target.isNotEmpty;
      }
    case Iterable<Object?> target:
      switch (name) {
        case 'length':
          return target.length;
        case 'isEmpty':
          return target.isEmpty;
        case 'isNotEmpty':
          return target.isNotEmpty;
        case 'first':
          return target.isEmpty ? null : target.first;
        case 'last':
          return target.isEmpty ? null : target.last;
      }
  }
  throw ViewException('can not read "$name" of ${_type(target)}');
}

/// `target.name(args)`: a function in a map, or a built in method
Object? callMethod(Object? target, String name, List<Object?> args) {
  Map<Object?, Object?>? map = _asMap(target);
  Object? function = map?[name];
  if (function is Function) return Function.apply(function, args);

  Object? arg(int i) => i < args.length ? args[i] : null;
  switch (target) {
    case String target:
      switch (name) {
        case 'toUpperCase':
          return target.toUpperCase();
        case 'toLowerCase':
          return target.toLowerCase();
        case 'trim':
          return target.trim();
        case 'contains':
          return target.contains(arg(0)! as String);
        case 'startsWith':
          return target.startsWith(arg(0)! as String);
        case 'endsWith':
          return target.endsWith(arg(0)! as String);
        case 'indexOf':
          return target.indexOf(arg(0)! as String);
        case 'split':
          return target.split(arg(0)! as String);
        case 'replaceAll':
          return target.replaceAll(arg(0)! as String, arg(1)! as String);
        case 'substring':
          return target.substring(arg(0)! as int, arg(1) as int?);
        case 'toString':
          return target;
      }
    case Iterable<Object?> target:
      switch (name) {
        case 'contains':
          return target.contains(arg(0));
        case 'join':
          return target.map(stringify).join(arg(0) as String? ?? ',');
        case 'indexOf':
          return target.toList().indexOf(arg(0));
      }
    case num target:
      switch (name) {
        case 'toStringAsFixed':
          return target.toStringAsFixed(arg(0)! as int);
        case 'round':
          return target.round();
        case 'floor':
          return target.floor();
        case 'ceil':
          return target.ceil();
        case 'abs':
          return target.abs();
        case 'toString':
          return target.toString();
      }
  }
  if (map != null && name == 'containsKey') return map.containsKey(arg(0));
  throw ViewException('${_type(target)} has no method "$name"');
}

String _type(Object? value) => value == null ? 'null' : '${value.runtimeType}';

String _describe(Expr expr) => switch (expr) {
  VariableExpr expr => '"${expr.name}"',
  _ => 'the value',
};

/// Reads an expression from its source.
class ExprParser {
  ExprParser(String source) : _tokens = _tokenize(source);

  final List<String> _tokens;
  int _pos = 0;

  /// one expression, and nothing after it
  Expr parse() {
    Expr expr = _expression();
    if (_pos < _tokens.length) throw _error('unexpected "${_tokens[_pos]}"');
    return expr;
  }

  /// expressions with commas between them, eg. the args of a tag
  List<Expr> parseList() {
    List<Expr> list = <Expr>[];
    while (_pos < _tokens.length) {
      list.add(_expression());
      if (_pos < _tokens.length) _expect(',');
    }
    return list;
  }

  Expr _expression() {
    Expr condition = _binary(0);
    if (!_match('?')) return condition;
    Expr then = _expression();
    _expect(':');
    return ConditionalExpr(condition, then, _expression());
  }

  static const List<List<String>> _levels = <List<String>>[
    <String>['??'],
    <String>['||'],
    <String>['&&'],
    <String>['==', '!=', '===', '!=='],
    <String>['<', '<=', '>', '>='],
    <String>['+', '-'],
    <String>['*', '/', '%', '~/'],
  ];

  Expr _binary(int level) {
    if (level == _levels.length) return _unary();
    Expr left = _binary(level + 1);
    while (_pos < _tokens.length && _levels[level].contains(_tokens[_pos])) {
      String op = _tokens[_pos++];
      left = BinaryExpr(op, left, _binary(level + 1));
    }
    return left;
  }

  Expr _unary() {
    if (_match('!')) return UnaryExpr('!', _unary());
    if (_match('-')) return UnaryExpr('-', _unary());
    return _postfix(_primary());
  }

  Expr _postfix(Expr expr) {
    while (true) {
      if (_match('.')) {
        expr = MemberExpr(expr, _name());
      } else if (_match('?.')) {
        expr = MemberExpr(expr, _name(), optional: true);
      } else if (_match('[')) {
        expr = IndexExpr(expr, _expression());
        _expect(']');
      } else if (_match('(')) {
        expr = CallExpr(expr, _items(')'));
      } else {
        return expr;
      }
    }
  }

  Expr _primary() {
    if (_pos >= _tokens.length) throw _error('the expression ends too soon');
    String token = _tokens[_pos++];
    if (token == '(') {
      Expr expr = _expression();
      _expect(')');
      return expr;
    }
    if (token == '[') return ListExpr(_items(']'));
    if (token == '{') return _map();
    if (token.startsWith("'") ||
        token.startsWith('"') ||
        token.startsWith('`')) {
      return LiteralExpr(_unquote(token));
    }
    int first = token.codeUnitAt(0);
    if (first >= 0x30 && first <= 0x39) return LiteralExpr(num.parse(token));
    if (!_isIdentifier(token)) throw _error('unexpected "$token"');
    return switch (token) {
      'true' => const LiteralExpr(true),
      'false' => const LiteralExpr(false),
      'null' => const LiteralExpr(null),
      _ => VariableExpr(token),
    };
  }

  /// `{ name: value, 'other name': value }`
  Expr _map() {
    Map<String, Expr> entries = <String, Expr>{};
    while (!_match('}')) {
      if (_pos >= _tokens.length) throw _error('{ is not closed with }');
      String key = _tokens[_pos++];
      if (key.startsWith("'") || key.startsWith('"')) {
        key = _unquote(key);
      } else if (!_isIdentifier(key)) {
        throw _error('bad map key "$key"');
      }
      // `{ name }` is short for `{ name: name }`
      if (_match(',') || (_pos < _tokens.length && _tokens[_pos] == '}')) {
        entries[key] = VariableExpr(key);
        continue;
      }
      _expect(':');
      entries[key] = _expression();
      if (!_match(',')) {
        _expect('}');
        break;
      }
    }
    return MapExpr(entries);
  }

  /// expressions with commas between them, up to [close]
  List<Expr> _items(String close) {
    List<Expr> items = <Expr>[];
    while (!_match(close)) {
      items.add(_expression());
      if (!_match(',')) {
        _expect(close);
        break;
      }
    }
    return items;
  }

  String _name() {
    if (_pos >= _tokens.length || !_isIdentifier(_tokens[_pos])) {
      throw _error('a name must come after "."');
    }
    return _tokens[_pos++];
  }

  /// true and move on when the next token is [token]
  bool _match(String token) {
    if (_pos < _tokens.length && _tokens[_pos] == token) {
      _pos++;
      return true;
    }
    return false;
  }

  void _expect(String token) {
    if (!_match(token)) {
      String found = _pos < _tokens.length ? '"${_tokens[_pos]}"' : 'the end';
      throw _error('expected "$token" but found $found');
    }
  }

  ViewException _error(String message) => ViewException(message);
}

const List<String> _operators = <String>[
  '===', '!==', '?.', '??', '==', '!=', '<=', '>=', '&&', '||', '~/', //
  '+', '-', '*', '/', '%', '<', '>', '!', '?', ':', '.', ',', //
  '(', ')', '[', ']', '{', '}', '=',
];

List<String> _tokenize(String source) {
  List<String> tokens = <String>[];
  int i = 0;
  while (i < source.length) {
    int c = source.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
      continue;
    }
    int start = i;
    if (c == 0x27 || c == 0x22 || c == 0x60) {
      i++;
      while (i < source.length && source.codeUnitAt(i) != c) {
        if (source.codeUnitAt(i) == 0x5C) i++;
        i++;
      }
      if (i >= source.length) throw ViewException('a string is not closed');
      tokens.add(source.substring(start, ++i));
    } else if (c >= 0x30 && c <= 0x39) {
      while (i < source.length && _isNumberChar(source, i)) {
        i++;
      }
      tokens.add(source.substring(start, i));
    } else if (_isIdentifierStart(c)) {
      while (i < source.length && _isIdentifierPart(source.codeUnitAt(i))) {
        i++;
      }
      tokens.add(source.substring(start, i));
    } else {
      String? op;
      for (String candidate in _operators) {
        if (source.startsWith(candidate, i)) {
          op = candidate;
          break;
        }
      }
      if (op == null) throw ViewException('unexpected "${source[i]}"');
      tokens.add(op);
      i += op.length;
    }
  }
  return tokens;
}

/// a digit, or a `.` with a digit after it
bool _isNumberChar(String source, int i) {
  int c = source.codeUnitAt(i);
  if (c >= 0x30 && c <= 0x39) return true;
  if (c != 0x2E || i + 1 >= source.length) return false;
  int next = source.codeUnitAt(i + 1);
  return next >= 0x30 && next <= 0x39;
}

bool _isIdentifierStart(int c) =>
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F ||
    c == 0x24;

bool _isIdentifierPart(int c) =>
    _isIdentifierStart(c) || (c >= 0x30 && c <= 0x39);

bool _isIdentifier(String token) =>
    _isIdentifierStart(token.codeUnitAt(0)) &&
    token.codeUnits.every(_isIdentifierPart);

/// the value of a string token, with `\n`, `\t` and `\x` escapes
String _unquote(String token) {
  StringBuffer out = StringBuffer();
  for (int i = 1; i < token.length - 1; i++) {
    String c = token[i];
    if (c != '\\') {
      out.write(c);
      continue;
    }
    String next = token[++i];
    out.write(switch (next) {
      'n' => '\n',
      't' => '\t',
      'r' => '\r',
      _ => next,
    });
  }
  return out.toString();
}
