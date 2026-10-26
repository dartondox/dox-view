import 'dart:io';

import 'package:dox_core/dox_core.dart';

import 'safe_string.dart';
import 'template_loader.dart';
import 'view_config.dart';
import 'view_engine.dart';

/// Render the template [name] (eg. `users/index`) as an HTML response.
///
/// With a session, the templates can also use `errors`, `old('field')`,
/// `session('key')`, `csrfToken()` and `csrfField()`. Every template can
/// use `request.path`, `request.method` and `request.query`. Components
/// and layouts see these too.
/// ```
/// DoxResponse index(DoxRequest req) {
///   return view(req, 'users/index', <String, dynamic>{'users': users});
/// }
/// ```
DoxResponse view(
  DoxRequest req,
  String name, [
  Map<String, dynamic> data = const <String, dynamic>{},
]) {
  String html = View.engine.render(name, data, View.requestData(req));
  return response(html).contentType(ContentType.html);
}

/// The template engine of the app. `ViewProvider` sets it up.
class View {
  static ViewEngine? _engine;

  /// the engine, with the default [ViewConfig] when it is not set up
  static ViewEngine get engine => _engine ??= _make(const ViewConfig());

  /// set up the engine with [config]. Globals added before with
  /// [global] are kept. The globals of [config] win on the same name.
  static void configure(ViewConfig config) {
    Map<String, Object?> before =
        _engine?.globals.vars ?? const <String, Object?>{};
    _engine = _make(config, before);
  }

  /// add a variable or function that every template can use
  /// ```
  /// View.global('year', DateTime.now().year);
  /// View.global('upper', (String text) => text.toUpperCase());
  /// ```
  static void global(String name, Object? value) {
    engine.global(name, value);
  }

  /// the HTML of the template [name] with [data], eg. for an email
  static String render(
    String name, [
    Map<String, dynamic> data = const <String, dynamic>{},
  ]) {
    return engine.render(name, data);
  }

  /// the variables `view()` adds for the request [req]
  static Map<String, Object?> requestData(DoxRequest req) {
    return <String, Object?>{
      'request': <String, Object?>{
        'path': req.uri.path,
        'method': req.method,
        'query': req.uri.queryParameters,
      },
      if (req.hasSession) ...<String, Object?>{
        'errors': req.session.errors,
        'old': req.session.old,
        'session': req.session.get,
        'csrfToken': () => req.session.token,
        'csrfField': () => SafeString(
          '<input type="hidden" name="_token" '
          'value="${escapeHtml(req.session.token)}">',
        ),
      },
    };
  }

  static ViewEngine _make(
    ViewConfig config, [
    Map<String, Object?> before = const <String, Object?>{},
  ]) {
    bool cache =
        config.cache ??
        !<String>[
          'development',
          'local',
        ].contains(Env.get<String>('APP_ENV').toLowerCase());
    return ViewEngine(
      FileTemplateLoader(config.path, extension: config.extension),
      cache: cache,
      globals: <String, Object?>{'route': _route, ...before, ...config.globals},
    );
  }
}

/// `route('users.show', {id: 5})` in a template
String _route(
  String name, [
  Map<Object?, Object?> params = const <Object?, Object?>{},
]) {
  return route(
    name,
    params: <String, Object?>{
      for (MapEntry<Object?, Object?> param in params.entries)
        '${param.key}': param.value,
    },
  );
}
