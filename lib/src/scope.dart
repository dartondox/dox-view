import 'view_exception.dart';

/// The variables a template can read. A scope looks in its parent for
/// a name it does not have.
class Scope {
  Scope(this.vars, [this.parent]);

  final Map<String, Object?> vars;
  final Scope? parent;

  /// the value of [name], null when no scope has it
  Object? lookup(String name) {
    Scope? scope = this;
    while (scope != null) {
      Object? value = scope.vars[name];
      if (value != null || scope.vars.containsKey(name)) return value;
      scope = scope.parent;
    }
    return null;
  }

  /// `@let`: a new variable in this scope
  void define(String name, Object? value) {
    vars[name] = value;
  }

  /// `@assign`: change the variable [name] where it is
  void assign(String name, Object? value) {
    Scope? scope = this;
    while (scope != null) {
      if (scope.vars.containsKey(name)) {
        scope.vars[name] = value;
        return;
      }
      scope = scope.parent;
    }
    throw ViewException('"$name" is not defined. Make it with @let first.');
  }
}
