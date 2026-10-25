import 'nodes.dart';
import 'scope.dart';
import 'template_loader.dart';
import 'template_parser.dart';
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
  }) : globals = Scope(<String, Object?>{...globals});

  final TemplateLoader loader;

  /// keep parsed templates. Turn it off in development, so a changed
  /// file shows on the next render.
  final bool cache;

  /// the variables and functions every template can use
  final Scope globals;

  final Map<String, Template> _templates = <String, Template>{};
  final Map<String, bool> _exists = <String, bool>{};

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
    Scope sharedScope = shared.isEmpty ? globals : Scope(shared, globals);
    RenderContext(this, sharedScope).renderTemplate(
      name,
      Scope(<String, Object?>{...data}, sharedScope),
      out,
      0,
    );
    return out.toString();
  }

  /// the parsed template [name]
  Template template(String name) {
    Template? found = _templates[name];
    if (found != null) return found;
    String? source = loader.load(name);
    if (source == null) throw ViewException('template "$name" not found');
    found = Template(name, TemplateParser(name, source, this).parse());
    if (cache) _templates[name] = found;
    return found;
  }

  /// true when there is a template [name]
  bool exists(String name) {
    if (!cache) return loader.load(name) != null;
    return _exists[name] ??= loader.load(name) != null;
  }
}
