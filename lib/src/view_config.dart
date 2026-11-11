import 'view_directive.dart';

/// The settings of `dox_view`. The path is from the folder where the
/// app runs (the project root).
/// ```
/// ViewConfig viewConfig = ViewConfig(
///   globals: <String, Object?>{'appName': 'My app'},
/// );
/// ```
class ViewConfig {
  const ViewConfig({
    this.path = 'resources/views',
    this.extension = '.dox.html',
    this.cache,
    this.globals = const <String, Object?>{},
    this.directives = const <String, ViewDirective>{},
    this.bladeWarnings = true,
    this.bladeOutput = true,
    this.strictVariables = true,
    this.stringZeroIsFalse = true,
  });

  /// The folder of the templates.
  final String path;

  /// The file extension of a template. `view('home')` reads
  /// `resources/views/home.dox.html`.
  final String extension;

  /// Keep parsed templates in memory. When null, it is on unless
  /// `APP_ENV` is `development` or `local`: there a changed template
  /// shows on the next request.
  final bool? cache;

  /// Variables and functions that every template can use.
  final Map<String, Object?> globals;

  /// The tags of the app, by name: `'datetime'` is `@datetime(...)`.
  final Map<String, ViewDirective> directives;

  /// Write a warning to `stderr` when a template has a Blade name that
  /// is not a Dox tag, like `@foreach`, `@endif` or `{!! !!}`. The
  /// output of the template does not change.
  final bool bladeWarnings;

  /// Print `true` as `1`, `false` as nothing, and a whole number like
  /// `10.0` as `10`. On by default. When false, they print as `true`, `false` and
  /// `10.0`.
  final bool bladeOutput;

  /// A variable that does not exist throws a `ViewException`. On by
  /// default. When false, it prints nothing. `@isset(x)`, `x ?? 'default'` and
  /// `x?.name` never throw.
  final bool strictVariables;

  /// The text `'0'` is false in `@if` and the other conditions. On by
  /// default. When false, `'0'` is true, like any text that is not
  /// empty.
  final bool stringZeroIsFalse;
}
