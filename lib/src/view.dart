import 'dart:io';

import 'package:dox_core/dox_core.dart';

import 'safe_string.dart';
import 'template_loader.dart';
import 'view_config.dart';
import 'view_directive.dart';
import 'view_engine.dart';

/// Render the template [name] (eg. `users/index`) as an HTML response.
///
/// With a session, the templates can also use `old('field')`,
/// `session('key')`, `csrfToken()`, `csrfField()` and `@csrf`. Every template can
/// use `errors` (empty with no session), `request.path`, `request.method`
/// and `request.query`. Components
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
  /// [global] and directives added before with [directive] are kept.
  /// The ones of [config] win on the same name.
  static void configure(ViewConfig config) {
    ViewEngine? old = _engine;
    _engine = _make(
      config,
      old?.globals.vars ?? const <String, Object?>{},
      old?.directives ?? const <String, ViewDirective>{},
    );
  }

  /// add the tag `@name(...)` for every template
  /// ```
  /// View.directive('datetime', DateTimeDirective());
  /// ```
  static void directive(String name, ViewDirective directive) {
    engine.directive(name, directive);
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
    return engine.render(name, data, _errors(const <String, Object?>{}));
  }

  /// `errors` is always there, so `{{ errors.email }}` prints nothing
  /// when there are no errors. An app global `errors` wins when there
  /// are no validation errors.
  static Map<String, Object?> _errors(Map<Object?, Object?> errors) {
    if (errors.isEmpty && engine.globals.vars.containsKey('errors')) {
      return const <String, Object?>{};
    }
    return <String, Object?>{'errors': errors};
  }

  /// the variables `view()` adds for the request [req]
  static Map<String, Object?> requestData(DoxRequest req) {
    return <String, Object?>{
      'request': <String, Object?>{
        'path': req.uri.path,
        'method': req.method,
        'query': req.uri.queryParameters,
      },
      ..._errors(
        req.hasSession ? req.session.errors : const <String, Object?>{},
      ),
      // for `@auth` and `@guest`
      r'$auth': req.auth?.isLoggedIn() ?? false,
      if (req.hasSession) ...<String, Object?>{
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
    Map<String, ViewDirective> directives = const <String, ViewDirective>{},
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
      environment: Env.get<String>('APP_ENV'),
      globals: <String, Object?>{'route': _route, ...before, ...config.globals},
      directives: <String, ViewDirective>{...directives, ...config.directives},
      bladeWarnings: config.bladeWarnings,
      bladeOutput: config.bladeOutput,
      strictVariables: config.strictVariables,
      stringZeroIsFalse: config.stringZeroIsFalse,
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
