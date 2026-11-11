import 'dart:convert';

import 'view_exception.dart';

/// HTML that is printed as it is. `{{ }}` does not escape it.
/// ```
/// View.global('logo', SafeString('<img src="/logo.svg">'));
/// ```
class SafeString {
  const SafeString(this.value);

  /// [value] as JSON for a page: `@json(value)` and `{{ json(value) }}`.
  /// `<`, `>`, `&`, `'` and the line separators U+2028 and U+2029 are
  /// written as `\uXXXX`. So the text is safe inside a `<script>` block
  /// and inside an attribute in single quotes. An object with `toJson()`
  /// works. A value that can not be JSON throws a [ViewException].
  factory SafeString.json(Object? value) {
    String text;
    try {
      text = jsonEncode(value);
    } on JsonUnsupportedObjectError catch (error) {
      throw ViewException(
        'can not make JSON of ${error.unsupportedObject.runtimeType}',
      );
    }
    // ponytail: one pass per character. One pass in all if it shows in
    // a profile.
    for (MapEntry<String, String> escape in _jsonEscapes.entries) {
      text = text.replaceAll(escape.key, escape.value);
    }
    return SafeString(text);
  }

  static const Map<String, String> _jsonEscapes = <String, String>{
    '<': r'\u003C',
    '>': r'\u003E',
    '&': r'\u0026',
    "'": r'\u0027',
    '\u2028': r'\u2028',
    '\u2029': r'\u2029',
  };

  final String value;

  @override
  String toString() => value;
}

/// `$attributes` of a component: its props as HTML attributes, like
/// `class="btn" id="save"`. `{{ $attributes }}` prints them, escaped.
/// Only text, numbers and `true` are attributes; `true` prints the
/// name alone. `null`, `false`, lists, maps and objects are left out.
/// With [blade] (the `bladeOutput` option), `10.0` prints as `10`.
class Attributes extends SafeString {
  Attributes(this.props, {this.blade = false}) : super(_render(props, blade));

  final Map<String, Object?> props;
  final bool blade;

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
    return SafeString(_render(merged, blade));
  }

  /// `{{ $attributes.except(['variant']) }}`: the attributes without
  /// these props, for props that are only for the logic of the
  /// component. It can go before `merge()`.
  Attributes except(Object? names) {
    Set<String> skip = <String>{
      if (names is Iterable<Object?>)
        for (Object? name in names) '$name'
      else if (names != null)
        '$names',
    };
    return Attributes(<String, Object?>{
      for (MapEntry<String, Object?> entry in props.entries)
        if (!skip.contains(entry.key)) entry.key: entry.value,
    }, blade: blade);
  }

  static final RegExp _name = RegExp(r'^[A-Za-z_:@][\w:.@-]*$');

  static String _render(Map<String, Object?> attributes, bool blade) {
    List<String> out = <String>[];
    for (MapEntry<String, Object?> entry in attributes.entries) {
      Object? value = entry.value;
      if (!_name.hasMatch(entry.key)) continue;
      if (value == true) {
        out.add(entry.key);
      } else if (value is String || value is num || value is SafeString) {
        String text = blade && value is double ? bladeDouble(value) : '$value';
        out.add('${entry.key}="${escapeHtml(text)}"');
      }
    }
    return out.join(' ');
  }
}

/// [value] as Blade prints it: `10.0` is `10`, `0.5` stays `0.5`
String bladeDouble(double value) {
  String text = value.toString();
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
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
