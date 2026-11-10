import 'scope.dart';

/// A tag made by the app, like `@datetime(post.createdAt)`.
/// ```
/// class DateTimeDirective implements ViewDirective {
///   @override
///   Object? render(List<Object?> args, Scope scope) {
///     Object? value = args[0];
///     DateTime time = value is DateTime ? value : DateTime.parse('$value');
///     return '${time.day}/${time.month}/${time.year}';
///   }
/// }
///
/// View.directive('datetime', DateTimeDirective());
/// ```
abstract interface class ViewDirective {
  /// the text to print for the tag. [args] are the values between `(`
  /// and `)`. [scope] has the variables of the template.
  ///
  /// The text is escaped, like `{{ }}`. Give a `SafeString` to print
  /// HTML as it is. `null` prints nothing.
  Object? render(List<Object?> args, Scope scope);
}
