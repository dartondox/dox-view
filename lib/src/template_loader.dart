import 'dart:io';

import 'view_exception.dart';

/// Finds the source of a template by its name, eg. `users/index`.
abstract class TemplateLoader {
  /// the source of [name], or null when there is no such template
  String? load(String name);
}

/// Reads templates from files: `users/index` is
/// `resources/views/users/index.dox.html`.
class FileTemplateLoader implements TemplateLoader {
  const FileTemplateLoader(this.path, {this.extension = '.dox.html'});

  final String path;
  final String extension;

  @override
  String? load(String name) {
    // a name can come from data: it must not leave the views folder
    if (name.startsWith('/') ||
        name.contains('\\') ||
        name.split('/').contains('..')) {
      throw ViewException('Bad template name "$name"');
    }
    File file = File('$path/$name$extension');
    if (!file.existsSync()) return null;
    return file.readAsStringSync();
  }
}

/// Templates from a map of name to source. Good for tests.
class MemoryTemplateLoader implements TemplateLoader {
  const MemoryTemplateLoader(this.templates);

  final Map<String, String> templates;

  @override
  String? load(String name) => templates[name];
}
