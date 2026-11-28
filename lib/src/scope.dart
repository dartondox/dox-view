import 'view_exception.dart';

/// The variables a template can read. A scope looks in its parent for
/// a name it does not have.
class Scope {
  Scope(this.vars, [this.parent])
    : strictVariables = parent?.strictVariables ?? false,
      stringZeroIsFalse = parent?.stringZeroIsFalse ?? false;

  /// the first scope of an engine. The scopes under it get its options.
  Scope.root(
    this.vars, {
    this.strictVariables = false,
    this.stringZeroIsFalse = false,
  }) : parent = null;

  final Map<String, Object?> vars;
  final Scope? parent;

  /// a template that reads a variable no scope has gets an error
  final bool strictVariables;

  /// the text `'0'` is false in a condition
  final bool stringZeroIsFalse;

  /// the value of [name], null when no scope has it
  Object? lookup(String name) {
    Map<String, Object?> vars = this.vars;
    Object? value = vars[name];
    if (value != null || vars.containsKey(name)) return value;
    return parent?.lookup(name);
  }

  /// true when this scope or a parent has [name], also with a null value
  bool has(String name) {
    return vars.containsKey(name) || (parent?.has(name) ?? false);
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
