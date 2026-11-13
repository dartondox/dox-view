import 'dart:io';

import 'package:dox_annotation/install.dart';
import 'package:dox_view/commands.dart';
import 'package:test/test.dart';

/// records the `dart` commands, runs nothing
class FakeRunner extends ProcessRunner {
  final List<String> calls = <String>[];

  @override
  Future<int> run(String executable, List<String> args, String folder) async {
    calls.add(args.join(' '));
    return 0;
  }
}

void main() {
  late Directory root;
  late FakeRunner runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dox_view_install_');
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('name: my_app\n\ndependencies:\n  dox_core: ^3.1.0\n');
    runner = FakeRunner();
    exitCode = 0;
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  String read(String path) => File('${root.path}/$path').readAsStringSync();

  Future<void> install(List<String> args) {
    return ViewInstallCommand(root: root, runner: runner).run(args);
  }

  /// every file of the app and its text
  Map<String, String> snapshot() {
    Map<String, String> files = <String, String>{};
    for (FileSystemEntity f in root.listSync(recursive: true)) {
      if (f is File) files[f.path] = f.readAsStringSync();
    }
    return files;
  }

  test('sets up views', () async {
    await install(<String>[]);
    expect(exitCode, 0);
    expect(runner.calls, <String>[
      'pub add dox_view',
      'pub add --dev dox_builder',
      'pub add --dev build_runner',
      'run build_runner build',
    ]);
    expect(
      read('lib/providers/view_provider.dart'),
      contains('AppViewProvider'),
    );
    expect(read('resources/views/welcome.dox.html'), contains('{{ name }}'));
  });

  test(
    'makes resources/views/emails only when the app has dox_mailer',
    () async {
      await install(<String>[]);
      expect(
        Directory('${root.path}/resources/views/emails').existsSync(),
        isFalse,
      );
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: my_app\n\ndependencies:\n  dox_mailer: ^3.1.0\n',
      );
      await install(<String>[]);
      expect(exitCode, 0);
      expect(
        Directory('${root.path}/resources/views/emails').existsSync(),
        isTrue,
      );
    },
  );

  test('a second run changes nothing, and own files stay', () async {
    await install(<String>[]);
    File('${root.path}/resources/views/welcome.dox.html')
        .writeAsStringSync('mine');
    File('${root.path}/lib/providers/view_provider.dart')
        .writeAsStringSync('// mine {');
    Map<String, String> before = snapshot();
    await install(<String>[]);
    expect(exitCode, 0);
    expect(snapshot(), before);
  });

  test('an existing views folder gets only the missing sample', () async {
    File('${root.path}/resources/views/home.dox.html')
      ..createSync(recursive: true)
      ..writeAsStringSync('home');
    await install(<String>[]);
    expect(read('resources/views/home.dox.html'), 'home');
    expect(read('resources/views/welcome.dox.html'), contains('Welcome'));
  });

  test('any option stops with exit code 1 and writes nothing', () async {
    for (List<String> args in <List<String>>[
      <String>['--x'],
      <String>['x'],
      <String>['--x='],
    ]) {
      Map<String, String> before = snapshot();
      await install(args);
      expect(exitCode, 1, reason: '$args');
      expect(runner.calls, isEmpty, reason: '$args');
      expect(snapshot(), before, reason: '$args');
      exitCode = 0;
    }
  });
}
