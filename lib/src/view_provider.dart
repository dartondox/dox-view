import 'package:dox_core/dox_core.dart';

import 'view.dart';
import 'view_config.dart';

/// Sets up the template engine in every isolate. Extend it in `lib/` so
/// the generated container finds it.
/// ```
/// class AppViewProvider extends ViewProvider {
///   AppViewProvider() : super(viewConfig);
/// }
/// ```
class ViewProvider extends DoxProvider {
  ViewProvider([this.config = const ViewConfig()]);

  final ViewConfig config;

  @override
  void setup() {
    View.configure(config);
  }
}
