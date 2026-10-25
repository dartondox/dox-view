/// A template has a syntax error, or an expression failed while it
/// rendered. The message names the template and the line.
class ViewException implements Exception {
  ViewException(this.message, {this.template, this.line});

  final String message;

  /// the name of the template, eg. `users/index`
  final String? template;

  final int? line;

  @override
  String toString() {
    if (template == null) return 'ViewException: $message';
    return 'ViewException: $message (in "$template", line $line)';
  }
}
