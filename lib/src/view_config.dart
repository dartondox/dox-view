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
}
