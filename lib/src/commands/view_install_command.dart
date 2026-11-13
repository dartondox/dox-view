import 'dart:io';

import 'package:dox_annotation/command.dart';
import 'package:dox_annotation/install.dart';

/// `dox view:install`. `dox add view` runs it. It sets up views in an
/// app: the provider, the `resources/views/` folder and one sample view.
/// It never overwrites a file, so it is safe to run twice.
class ViewInstallCommand extends Command {
  /// [root] is the app folder (the current folder by default). [runner]
  /// runs `dart`, tests pass a fake one.
  ViewInstallCommand({this.root, this.runner});

  final Directory? root;
  final ProcessRunner? runner;

  @override
  String get name => 'view:install';

  @override
  String get description => 'Set up views in this app';

  @override
  String get usage => 'view:install';

  @override
  Future<void> run(List<String> args) async {
    if (args.isNotEmpty) {
      print('Unknown option. view:install has no options.');
      exitCode = 1;
      return;
    }
    Installer installer = Installer(root: root, runner: runner);

    await installer.addDependency('dox_view');
    await installer.addDependency('dox_builder', dev: true);
    await installer.addDependency('build_runner', dev: true);

    installer.writeFile('lib/providers/view_provider.dart', provider);
    installer.makeFolder('resources/views');
    installer.writeFile('resources/views/welcome.dox.html', welcomeView);

    await installer.buildRunner();
    installer.printSummary(<String>[
      "Render it in a controller: `return view(req, 'welcome', "
          "<String, dynamic>{'name': 'Dox'});`.",
      'Make more views with `dox make:view emails/welcome`.',
    ]);
  }

  /// `lib/providers/view_provider.dart`, the same as the docs show
  static const String provider = '''
import 'package:dox_view/dox_view.dart';

class AppViewProvider extends ViewProvider {
  AppViewProvider() : super(const ViewConfig());
}
''';

  /// `resources/views/welcome.dox.html`, a small sample
  static const String welcomeView = '''
<h1>Welcome to {{ name }}</h1>
''';
}
