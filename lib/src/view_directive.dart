import 'scope.dart';

/// A tag made by the app, like `@datetime(post.createdAt)`.
/// ```
/// class DateTimeDirective implements ViewDirective {
///   @override
///   Object? render(List<Object?> args, Scope scope) {
///     return (args[0] as DateTime).toIso8601String();
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
