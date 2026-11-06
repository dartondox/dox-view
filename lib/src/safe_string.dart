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

/// `$attributes` of a component: its props as HTML attributes, like
/// `class="btn" id="save"`. `{{ $attributes }}` prints them, escaped.
/// Only text, numbers and `true` are attributes; `true` prints the
/// name alone. `null`, `false`, lists, maps and objects are left out.
class Attributes extends SafeString {
  Attributes(this.props) : super(_render(props));

  final Map<String, Object?> props;

  /// `$attributes.type` reads a prop
  Map<String, Object?> toJson() => props;

  /// `{{ $attributes.merge({ class: 'btn', type: 'button' }) }}`: the
  /// [defaults], then the props. A prop wins, but `class` is joined.
  SafeString merge(Object? defaults) {
    Map<String, Object?> merged = <String, Object?>{
      if (defaults is Map<Object?, Object?>)
        for (MapEntry<Object?, Object?> entry in defaults.entries)
          '${entry.key}': entry.value,
    };
    for (MapEntry<String, Object?> entry in props.entries) {
      String before = '${merged[entry.key] ?? ''}';
      String value = '${entry.value ?? ''}';
      if (entry.key == 'class' && before.isNotEmpty) {
        merged['class'] = value.isEmpty ? before : '$before $value';
      } else {
        merged[entry.key] = entry.value;
      }
    }
    return SafeString(_render(merged));
  }

  static final RegExp _name = RegExp(r'^[A-Za-z_:@][\w:.@-]*$');

  static String _render(Map<String, Object?> attributes) {
    List<String> out = <String>[];
    for (MapEntry<String, Object?> entry in attributes.entries) {
      Object? value = entry.value;
      if (!_name.hasMatch(entry.key)) continue;
      if (value == true) {
        out.add(entry.key);
      } else if (value is String || value is num || value is SafeString) {
        out.add('${entry.key}="${escapeHtml('$value')}"');
      }
    }
    return out.join(' ');
  }
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
