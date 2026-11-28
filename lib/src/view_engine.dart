import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'expression.dart' show jsonCache;
import 'nodes.dart';
import 'safe_string.dart';
import 'scope.dart';
import 'template_loader.dart';
import 'template_parser.dart';
import 'utf8_sink.dart';
import 'view_directive.dart';
import 'view_exception.dart';

/// Parses and renders templates. Use `View` in a Dox app; use this
/// class to render templates on their own.
/// ```
/// ViewEngine engine = ViewEngine(MemoryTemplateLoader(<String, String>{
///   'hello': 'Hello {{ name }}!',
/// }));
/// engine.render('hello', <String, Object?>{'name': 'Dox'}); // Hello Dox!
/// ```
class ViewEngine {
  ViewEngine(
    this.loader, {
    this.cache = true,
    Map<String, Object?> globals = const <String, Object?>{},
    String? environment,
    Map<String, ViewDirective> directives = const <String, ViewDirective>{},
    this.bladeWarnings = true,
    this.warningSink,
    this.bladeOutput = false,
    bool strictVariables = false,
    bool stringZeroIsFalse = false,
  }) : globals = Scope.root(
         <String, Object?>{'json': SafeString.json, ...globals},
         strictVariables: strictVariables,
         stringZeroIsFalse: stringZeroIsFalse,
       ),
       environment = environment ?? Platform.environment['APP_ENV'] ?? '' {
    for (MapEntry<String, ViewDirective> entry in directives.entries) {
      directive(entry.key, entry.value);
    }
  }

  final TemplateLoader loader;

  /// keep parsed templates. Turn it off in development, so a changed
  /// file shows on the next render.
  final bool cache;

  /// the variables and functions every template can use
  final Scope globals;

  /// the app environment for `@env` and `@production`. By default it is
  /// `APP_ENV`.
  final String environment;

  /// write a warning when a template has a Blade name that is not a
  /// Dox tag, like `@foreach` or `{!! !!}`
  final bool bladeWarnings;

  /// where the warnings go. By default it is `stderr`.
  final StringSink? warningSink;

  /// print `true` as `1`, `false` as nothing, and a number like `10.0`
  /// as `10`. Off by default: they print as `true`, `false` and `10.0`.
  final bool bladeOutput;

  /// a variable that does not exist throws a [ViewException]. Off by
  /// default: it prints nothing.
  bool get strictVariables => globals.strictVariables;

  /// the text `'0'` is false in a condition. Off by default: `'0'` is
  /// true.
  bool get stringZeroIsFalse => globals.stringZeroIsFalse;

  final Map<String, Template> _templates = <String, Template>{};
  final Set<String> _warned = <String>{};
  final Map<String, bool> _exists = <String, bool>{};
  final Map<String, ViewDirective> _directives = <String, ViewDirective>{};

  static final RegExp _directiveName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// the tags of the app, by name
  Map<String, ViewDirective> get directives =>
      Map<String, ViewDirective>.unmodifiable(_directives);

  /// add the tag `@name(...)`. It prints what [directive] gives.
  /// A name of a built-in tag, like `if`, throws a [ViewException].
  void directive(String name, ViewDirective directive) {
    if (!_directiveName.hasMatch(name)) {
      throw ViewException(
        'bad directive name "$name". Use letters, digits and _ only.',
      );
    }
    if (TemplateParser.isBuiltIn(name)) {
      throw ViewException(
        '@$name is a built-in tag. Use another name for the directive.',
      );
    }
    _directives[name] = directive;
    // a template parsed before has `@name(...)` as plain text
    _templates.clear();
  }

  /// the directive of the tag [name], null when there is none
  ViewDirective? directiveFor(String name) => _directives[name];

  /// write the warning [message], one time only. A template that is
  /// parsed again, with the cache off, does not repeat it.
  void warn(String message) {
    if (!bladeWarnings || !_warned.add(message)) return;
    (warningSink ?? stderr).writeln('dox_view: warning: $message');
  }

  /// add a variable or function that every template can use
  void global(String name, Object? value) {
    globals.define(name, value);
  }

  /// the HTML of the template [name] with [data]. Components do not see
  /// [data], but they see [shared], eg. the request helpers.
  String render(
    String name, [
    Map<String, Object?> data = const <String, Object?>{},
    Map<String, Object?> shared = const <String, Object?>{},
  ]) {
    StringBuffer out = StringBuffer();
    RenderContext ctx = _render(name, data, shared, out);
    return ctx.finish(out.toString());
  }

  /// [render] as UTF-8 bytes: the same bytes as `utf8.encode(render(...))`.
  /// The text is escaped and encoded in one pass, so a page is faster
  /// than [render] and an encode.
  Uint8List renderBytes(
    String name, [
    Map<String, Object?> data = const <String, Object?>{},
    Map<String, Object?> shared = const <String, Object?>{},
  ]) {
    // one buffer for the renders of this engine. A render inside a
    // render (eg. in a directive) gets a new one.
    Utf8Sink out = _spare ?? Utf8Sink(4096);
    _spare = null;
    try {
      RenderContext ctx = _render(name, data, shared, out);
      Uint8List bytes = out.takeBytes();
      // `@stack` marks are filled in the text. Rare, so this path can be
      // slow.
      if (!ctx.hasStacks) return bytes;
      return utf8.encode(ctx.finish(utf8.decode(bytes)));
    } finally {
      out.reset();
      // ponytail: a buffer past 1 MB is dropped, so one huge page does not
      // keep its memory
      if (out.capacity <= _spareLimit) _spare = out;
    }
  }

  static const int _spareLimit = 1 << 20;

  Utf8Sink? _spare;

  RenderContext _render(
    String name,
    Map<String, Object?> data,
    Map<String, Object?> shared,
    StringSink out,
  ) {
    Scope sharedScope = shared.isEmpty ? globals : Scope(shared, globals);
    // a new toJson() cache for this render; keep the outer one for a
    // render inside a render
    Expando<Map<Object?, Object?>>? outer = jsonCache;
    jsonCache = Expando<Map<Object?, Object?>>();
    RenderContext ctx = RenderContext(this, sharedScope);
    try {
      ctx.renderTemplate(
        name,
        Scope(<String, Object?>{...data}, sharedScope),
        out,
        0,
      );
    } finally {
      jsonCache = outer;
    }
    return ctx;
  }

  /// the parsed template [name]
  Template template(String name) {
    Template? found = _templates[name];
    if (found != null) return found;
    String? source = loader.load(name);
    if (source == null) throw ViewException('template "$name" not found');
    found = TemplateParser(name, source, this).parse();
    if (cache) _templates[name] = found;
    return found;
  }

  /// true when there is a template [name]
  bool exists(String name) {
    if (!cache) return loader.load(name) != null;
    return _exists[name] ??= loader.load(name) != null;
  }
}
