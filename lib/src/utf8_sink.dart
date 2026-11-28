import 'dart:typed_data';

/// Writes text as UTF-8 bytes, with the same bytes as `utf8.encode`.
/// [writeEscaped] escapes HTML in the same pass, so a page is encoded
/// one time. For internal use.
class Utf8Sink implements StringSink {
  Utf8Sink([int size = 1024]) : _buffer = Uint8List(size < 64 ? 64 : size);

  Uint8List _buffer;
  int _length = 0;

  /// the number of bytes written
  int get length => _length;

  /// the bytes written so far, in a list of their own
  Uint8List takeBytes() => Uint8List.sublistView(_buffer, 0, _length);

  /// add [bytes] as they are
  void addBytes(Uint8List bytes) {
    int count = bytes.length;
    _ensure(count);
    _buffer.setRange(_length, _length + count, bytes);
    _length += count;
  }

  @override
  void write(Object? object) {
    String text = object is String ? object : '$object';
    int count = text.length;
    // a code unit is at most 3 bytes
    _ensure(count * 3);
    Uint8List out = _buffer;
    int at = _length;
    for (int i = 0; i < count; i++) {
      int unit = text.codeUnitAt(i);
      if (unit < 0x80) {
        out[at++] = unit;
      } else {
        at = _multi(out, at, text, unit, i);
        if (_isPair(text, unit, i)) i++;
      }
    }
    _length = at;
  }

  /// write [text] with `&`, `<`, `>`, `"` and `'` as HTML entities, like
  /// `escapeHtml`
  void writeEscaped(String text) {
    int count = text.length;
    // `&quot;` is the longest: 6 bytes for one code unit
    _ensure(count * 6);
    Uint8List out = _buffer;
    int at = _length;
    for (int i = 0; i < count; i++) {
      int unit = text.codeUnitAt(i);
      if (unit > 0x3E) {
        if (unit < 0x80) {
          out[at++] = unit;
        } else {
          at = _multi(out, at, text, unit, i);
          if (_isPair(text, unit, i)) i++;
        }
        continue;
      }
      switch (unit) {
        case 0x26: // &amp;
          out[at++] = 0x26;
          out[at++] = 0x61;
          out[at++] = 0x6D;
          out[at++] = 0x70;
          out[at++] = 0x3B;
        case 0x3C: // &lt;
          out[at++] = 0x26;
          out[at++] = 0x6C;
          out[at++] = 0x74;
          out[at++] = 0x3B;
        case 0x3E: // &gt;
          out[at++] = 0x26;
          out[at++] = 0x67;
          out[at++] = 0x74;
          out[at++] = 0x3B;
        case 0x22: // &quot;
          out[at++] = 0x26;
          out[at++] = 0x71;
          out[at++] = 0x75;
          out[at++] = 0x6F;
          out[at++] = 0x74;
          out[at++] = 0x3B;
        case 0x27: // &#39;
          out[at++] = 0x26;
          out[at++] = 0x23;
          out[at++] = 0x33;
          out[at++] = 0x39;
          out[at++] = 0x3B;
        default:
          out[at++] = unit;
      }
    }
    _length = at;
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    bool first = true;
    for (Object? object in objects) {
      if (!first && separator.isNotEmpty) write(separator);
      write(object);
      first = false;
    }
  }

  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  void _ensure(int more) {
    int need = _length + more;
    if (need <= _buffer.length) return;
    int size = _buffer.length * 2;
    while (size < need) {
      size *= 2;
    }
    _buffer = Uint8List(size)..setRange(0, _length, _buffer);
  }

  /// true when [unit] at [i] starts a surrogate pair
  static bool _isPair(String text, int unit, int i) {
    return unit >= 0xD800 &&
        unit <= 0xDBFF &&
        i + 1 < text.length &&
        _isLow(text.codeUnitAt(i + 1));
  }

  static bool _isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  /// writes the non-ASCII [unit] at [i]. A lone surrogate is U+FFFD, as
  /// `utf8.encode` writes it.
  static int _multi(Uint8List out, int at, String text, int unit, int i) {
    if (unit < 0x800) {
      out[at++] = 0xC0 | (unit >> 6);
      out[at++] = 0x80 | (unit & 0x3F);
      return at;
    }
    if (unit >= 0xD800 && unit <= 0xDFFF) {
      if (!_isPair(text, unit, i)) {
        out[at++] = 0xEF;
        out[at++] = 0xBF;
        out[at++] = 0xBD;
        return at;
      }
      int code =
          0x10000 + ((unit - 0xD800) << 10) + (text.codeUnitAt(i + 1) - 0xDC00);
      out[at++] = 0xF0 | (code >> 18);
      out[at++] = 0x80 | ((code >> 12) & 0x3F);
      out[at++] = 0x80 | ((code >> 6) & 0x3F);
      out[at++] = 0x80 | (code & 0x3F);
      return at;
    }
    out[at++] = 0xE0 | (unit >> 12);
    out[at++] = 0x80 | ((unit >> 6) & 0x3F);
    out[at++] = 0x80 | (unit & 0x3F);
    return at;
  }
}
