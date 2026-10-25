import 'view_exception.dart';

enum TokenKind { text, output, rawOutput, tag }

/// A piece of a template: text, `{{ }}`, `{{{ }}}` or a `@tag(...)`.
class Token {
  Token(
    this.kind,
    this.value,
    this.line, {
    this.name = '',
    this.args,
    this.selfClosing = false,
    this.standalone = false,
  });

  final TokenKind kind;

  /// the text, the expression, or the source of the whole tag
  String value;

  final int line;

  /// the tag name, eg. `if` or `form.input`
  final String name;

  /// the source between the tag's `(` and `)`, null with no `()`
  final String? args;

  /// `@!component(...)`: a tag with no body and no `@end`
  final bool selfClosing;

  /// the tag is alone on its line, so the line is removed from the output
  final bool standalone;
}

/// Splits the source of a template into tokens.
class Lexer {
  Lexer(this.source, this.template);

  final String source;
  final String template;

  final List<Token> _tokens = <Token>[];
  final StringBuffer _text = StringBuffer();
  int _textLine = 1;
  int _pos = 0;
  int _line = 1;

  /// where the last tag ended: a tag can start right there, eg. `@end@if`
  int _tagEnd = -1;

  List<Token> tokenize() {
    while (_pos < source.length) {
      int next = _nextSpecial(_pos);
      _addText(source.substring(_pos, next));
      _advance(next);
      if (_pos >= source.length) break;

      if (source.startsWith('@{{', _pos)) {
        _addText('{{');
        _advance(_pos + 3);
      } else if (source.startsWith('@@', _pos)) {
        _addText('@');
        _advance(_pos + 2);
      } else if (source.startsWith('{{--', _pos)) {
        _comment();
      } else if (source.startsWith('{{{', _pos)) {
        _output('}}}', TokenKind.rawOutput);
      } else if (source.startsWith('{{', _pos)) {
        _output('}}', TokenKind.output);
      } else if (_isTagStart(_pos)) {
        _tag();
      } else {
        _addText(source[_pos]);
        _advance(_pos + 1);
      }
    }
    _flushText();
    return _tokens;
  }

  /// the index of the next `@` or `{` from [from], or the end
  int _nextSpecial(int from) {
    for (int i = from; i < source.length; i++) {
      int c = source.codeUnitAt(i);
      if (c == 0x40 || c == 0x7B) return i;
    }
    return source.length;
  }

  void _comment() {
    int end = source.indexOf('--}}', _pos + 4);
    if (end == -1) _fail('{{-- is not closed with --}}');
    _advance(end + 4);
  }

  void _output(String close, TokenKind kind) {
    int line = _line;
    int start = _pos + close.length;
    int end = _scanTo(start, close);
    if (end == -1) _fail('${'{' * close.length} is not closed with $close');
    String expression = source.substring(start, end).trim();
    if (expression.isEmpty) _fail('empty ${'{' * close.length} $close');
    _flushText();
    _tokens.add(Token(kind, expression, line));
    _advance(end + close.length);
  }

  /// `@name`, `@name(...)` or `@!name(...)`
  void _tag() {
    int line = _line;
    int start = _pos;
    int i = _pos + 1;
    bool selfClosing = source.codeUnitAt(i) == 0x21; // !
    if (selfClosing) i++;
    int nameStart = i;
    while (i < source.length && _isNameChar(source.codeUnitAt(i))) {
      i++;
    }
    // a dot at the end is the end of a sentence, not the name
    while (source.codeUnitAt(i - 1) == 0x2E) {
      i--;
    }
    String name = source.substring(nameStart, i);

    String? args;
    int end = i;
    int paren = i;
    while (paren < source.length &&
        (source[paren] == ' ' || source[paren] == '\t')) {
      paren++;
    }
    if (paren < source.length && source[paren] == '(') {
      int close = _closingParen(paren);
      if (close == -1) _fail('@$name( is not closed with )');
      args = source.substring(paren + 1, close);
      end = close + 1;
    }

    _flushText();
    _tokens.add(
      Token(
        TokenKind.tag,
        source.substring(start, end),
        line,
        name: name,
        args: args,
        selfClosing: selfClosing,
        standalone: _aloneOnLine(start, end),
      ),
    );
    _advance(end);
    _tagEnd = end;
  }

  /// an `@` that starts a tag: not in the middle of a word or an email
  bool _isTagStart(int at) {
    if (at > 0 && at != _tagEnd) {
      int before = source.codeUnitAt(at - 1);
      if (_isNameChar(before)) return false;
    }
    int i = at + 1;
    if (i < source.length && source.codeUnitAt(i) == 0x21) i++;
    return i < source.length && _isLetter(source.codeUnitAt(i));
  }

  /// only spaces between the line start and [start], and between [end]
  /// and the line end
  bool _aloneOnLine(int start, int end) {
    for (int i = start - 1; i >= 0 && source[i] != '\n'; i--) {
      if (source[i] != ' ' && source[i] != '\t') return false;
    }
    for (int i = end; i < source.length && source[i] != '\n'; i++) {
      if (source[i] != ' ' && source[i] != '\t' && source[i] != '\r') {
        return false;
      }
    }
    return true;
  }

  /// the index of [close] after [from], outside strings and `{ }`
  int _scanTo(int from, String close) {
    int depth = 0;
    for (int i = from; i < source.length; i++) {
      String c = source[i];
      if (c == "'" || c == '"' || c == '`') {
        i = _stringEnd(i);
        if (i == -1) return -1;
      } else if (depth == 0 && source.startsWith(close, i)) {
        return i;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
      }
    }
    return -1;
  }

  /// the index of the `)` that closes the `(` at [open]
  int _closingParen(int open) {
    int depth = 0;
    for (int i = open; i < source.length; i++) {
      String c = source[i];
      if (c == "'" || c == '"' || c == '`') {
        i = _stringEnd(i);
        if (i == -1) return -1;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// the index of the quote that ends the string that starts at [start]
  int _stringEnd(int start) {
    String quote = source[start];
    for (int i = start + 1; i < source.length; i++) {
      if (source[i] == '\\') {
        i++;
      } else if (source[i] == quote) {
        return i;
      }
    }
    return -1;
  }

  void _addText(String text) {
    if (text.isEmpty) return;
    if (_text.isEmpty) _textLine = _line;
    _text.write(text);
  }

  void _flushText() {
    if (_text.isEmpty) return;
    _tokens.add(Token(TokenKind.text, _text.toString(), _textLine));
    _text.clear();
  }

  /// move to [to] and count the lines on the way
  void _advance(int to) {
    for (int i = _pos; i < to; i++) {
      if (source.codeUnitAt(i) == 0x0A) _line++;
    }
    _pos = to;
  }

  Never _fail(String message) {
    throw ViewException(message, template: template, line: _line);
  }
}

bool _isLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;

bool _isNameChar(int c) =>
    _isLetter(c) || (c >= 0x30 && c <= 0x39) || c == 0x2E;
