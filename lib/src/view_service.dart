import 'package:dox_core/dox_core.dart';

import 'view.dart';
import 'view_config.dart';

/// Sets up the template engine in every isolate. Extend it in `lib/` so
/// the generated container finds it.
/// ```
/// class AppViewService extends ViewService {
///   AppViewService() : super(viewConfig);
/// }
/// ```
class ViewService implements DoxService {
  ViewService([this.config = const ViewConfig()]);

  final ViewConfig config;

  @override
  void setup() {
    View.configure(config);
  }
}
