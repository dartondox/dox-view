/// HTML that is printed as it is. `{{ }}` does not escape it.
/// ```
/// View.global('logo', SafeString('<img src="/logo.svg">'));
/// ```
class SafeString {
  const SafeString(this.value);

  final String value;

  @override
  String toString() => value;
}

/// [text] with `&`, `<`, `>`, `"` and `'` as HTML entities
String escapeHtml(String text) {
  StringBuffer? out;
  int start = 0;
  for (int i = 0; i < text.length; i++) {
    String? entity = switch (text.codeUnitAt(i)) {
      0x26 => '&amp;',
      0x3C => '&lt;',
      0x3E => '&gt;',
      0x22 => '&quot;',
      0x27 => '&#39;',
      _ => null,
    };
    if (entity == null) continue;
    out ??= StringBuffer();
    out
      ..write(text.substring(start, i))
      ..write(entity);
    start = i + 1;
  }
  // most text has nothing to escape: no copy
  if (out == null) return text;
  out.write(text.substring(start));
  return out.toString();
}
