import 'dart:io';

import 'package:dox_core/dox_core.dart';
import 'package:dox_core/testing.dart';
import 'package:dox_view/dox_view.dart';
import 'package:test/test.dart';

class ViewRouter extends Router {
  @override
  List<dynamic> get middleware => <dynamic>[
    const SessionMiddleware(),
    const CsrfMiddleware(),
  ];

  @override
  void register() {
    Route.get('/users/{id}', (DoxRequest req) {
      return view(req, 'users/show', <String, dynamic>{'name': '<Ann>'});
    }).name('users.show');
    Route.get('/form', (DoxRequest req) => view(req, 'form'));
    Route.get('/edit', (DoxRequest req) => view(req, 'edit'));
    Route.get('/field', (DoxRequest req) => view(req, 'field'));
    Route.post('/form', (DoxRequest req) {
      req.session.flashErrors(<String, String>{
        'email': 'The email is taken',
      }, input: req.all());
      return redirect('/form');
    });
  }
}

class PlainRouter extends Router {
  @override
  void register() {
    Route.get('/plain', (DoxRequest req) => view(req, 'errors'));
    Route.get('/auth', (DoxRequest req) {
      if (req.uri.queryParameters.containsKey('in')) req.auth = LoggedIn();
      return view(req, 'auth');
    });
  }
}

class LoggedIn implements IAuth {
  @override
  bool isLoggedIn() => true;

  @override
  T? user<T>() => null;

  @override
  Map<String, dynamic>? toJson() => null;

  @override
  Future<void> verifyToken(IDoxRequest req) async {}
}

class Upper implements ViewDirective {
  @override
  Object? render(List<Object?> args, Scope scope) => '${args[0]}'.toUpperCase();
}

void main() {
  late DoxTestClient client;
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('dox_view_');
    await Directory('${dir.path}/users').create();
    await File('${dir.path}/users/show.dox.html').writeAsString(
      '<h1>{{ name }}</h1>'
      "<a href=\"{{ route('users.show', { id: 7 }) }}\">{{ request.path }}</a>",
    );
    // the form is in a layout component: it sees the request helpers
    await File('${dir.path}/form.dox.html').writeAsString(
      "@component('form_layout')"
      '<input name="email" value="{{ old(\'email\') }}">'
      "{{ errors.email ?? '' }}"
      '@end',
    );
    await File('${dir.path}/form_layout.dox.html').writeAsString(
      '<form method="POST" action="{{ request.path }}">{{ csrfField() }}'
      '{{ \$slots.main }}</form>',
    );
    await File('${dir.path}/edit.dox.html').writeAsString(
      '<form method="POST" action="/form">\n'
      '@csrf\n'
      "@method('PUT')\n"
      '</form>\n',
    );
    await File('${dir.path}/field.dox.html').writeAsString(
      "@error('email')\n<p>{{ message }}</p>\n@else\nfine\n@end\n",
    );
    await File('${dir.path}/auth.dox.html')
        .writeAsString('@auth\nin\n@else\nout\n@end\n');
    await File('${dir.path}/errors.dox.html')
        .writeAsString('[{{ errors.email }}]');
    View.configure(ViewConfig(path: dir.path, cache: false));
    client = await DoxTestClient.start(
      AppConfig(
        appKey: '4HyiSrq4N5Nfg6bOadIhbFEI8zbUkpxt',
        routers: <Router>[ViewRouter(), PlainRouter()],
      ),
    );
  });

  tearDownAll(() async {
    await client.close();
    await dir.delete(recursive: true);
  });

  test('view() renders a file as HTML', () async {
    TestResponse res = await client.get('/users/5');
    expect(res.status, 200);
    expect(res.headers['content-type'], contains('text/html'));
    expect(res.body, '<h1>&lt;Ann&gt;</h1><a href="/users/7">/users/5</a>');
  });

  test('forms get the CSRF field, old input and errors', () async {
    TestResponse page = await client.get('/form');
    String token = RegExp(r'name="_token" value="([^"]+)"')
        .firstMatch(page.body)![1]!;
    Map<String, String> cookies = page.cookies;

    TestResponse post = await client
        .withCookies(cookies)
        .post(
          '/form',
          body: <String, String>{'_token': token, 'email': 'a@b.c'},
        );
    expect(post.status, 302);

    TestResponse back = await client
        .withCookies(<String, String>{...cookies, ...post.cookies})
        .get('/form');
    expect(back.body, contains('value="a@b.c"'));
    expect(back.body, contains('The email is taken'));
    expect(back.body, contains('action="/form"'));
  });

  test('@csrf prints the token of the session, and @method', () async {
    TestResponse page = await client.get('/edit');
    expect(
      page.body,
      contains('<input type="hidden" name="_method" value="PUT">'),
    );
    String token = RegExp(
      r'<input type="hidden" name="_token" value="([^"]+)">',
    ).firstMatch(page.body)![1]!;

    TestResponse post = await client
        .withCookies(page.cookies)
        .post('/form', body: <String, String>{'_token': token});
    expect(post.status, 302);
  });

  test('@error shows the flashed error of the field', () async {
    TestResponse page = await client.get('/form');
    String token = RegExp(r'name="_token" value="([^"]+)"')
        .firstMatch(page.body)![1]!;
    TestResponse post = await client
        .withCookies(page.cookies)
        .post('/form', body: <String, String>{'_token': token});
    TestResponse back = await client
        .withCookies(<String, String>{...page.cookies, ...post.cookies})
        .get('/field');
    expect(back.body, '<p>The email is taken</p>\n');
    // no errors, and no session at all
    expect((await client.get('/field')).body, 'fine\n');
    expect(View.render('field'), 'fine\n');
  });

  test('ViewConfig gives its options to the engine', () async {
    await File('${dir.path}/options.dox.html')
        .writeAsString("{{ on }}|@if('0') zero @end|{{ missing ?? 'none' }}");
    Map<String, dynamic> data = <String, dynamic>{'on': true};
    expect(View.render('options', data), 'true| zero |none');
    expect(View.engine.bladeWarnings, isTrue);
    View.configure(
      ViewConfig(
        path: dir.path,
        cache: false,
        bladeWarnings: false,
        bladeOutput: true,
        strictVariables: true,
        stringZeroIsFalse: true,
      ),
    );
    try {
      expect(View.render('options', data), '1||none');
      expect(View.engine.bladeWarnings, isFalse);
      expect(() => View.render('options'), throwsA(isA<ViewException>()));
    } finally {
      View.configure(ViewConfig(path: dir.path, cache: false));
    }
  });

  test('@csrf with no session is an error', () {
    expect(() => View.render('edit'), throwsA(isA<ViewException>()));
  });

  test('View.directive adds a tag, and configure keeps it', () async {
    await File('${dir.path}/tag.dox.html').writeAsString('@upper(name)');
    View.directive('upper', Upper());
    expect(View.render('tag', <String, dynamic>{'name': 'ann'}), 'ANN');
    View.configure(ViewConfig(path: dir.path, cache: false));
    expect(View.render('tag', <String, dynamic>{'name': 'ann'}), 'ANN');
  });

  test('errors is empty with no session and in View.render', () async {
    TestResponse res = await client.get('/plain');
    expect(res.status, 200);
    expect(res.body, '[]');
    expect(View.render('errors'), '[]');
  });

  test('@auth and @guest use req.auth', () async {
    expect((await client.get('/auth')).body, 'out\n');
    expect((await client.get('/auth?in=1')).body, 'in\n');
  });

  test('an app global errors wins when there are no errors', () async {
    View.global('errors', <String, String>{'email': 'global'});
    try {
      expect((await client.get('/plain')).body, '[global]');
      expect(View.render('errors'), '[global]');
    } finally {
      View.engine.globals.vars.remove('errors');
    }
  });

  test('View.render gives a string, eg. for mail', () {
    expect(
      View.render('users/show', <String, dynamic>{
        'name': 'Bob',
        'request': <String, String>{'path': '/'},
      }),
      '<h1>Bob</h1><a href="/users/7">/</a>',
    );
  });

  test('configure keeps globals that were added before', () {
    View.global('year', 2026);
    View.global('appName', 'old');
    View.configure(
      ViewConfig(
        path: dir.path,
        cache: false,
        globals: <String, Object?>{'appName': 'new'},
      ),
    );
    expect(View.engine.globals.lookup('year'), 2026);
    expect(View.engine.globals.lookup('appName'), 'new');
    expect(View.engine.globals.lookup('route'), isNotNull);
  });

  test('a template name can not leave the views folder', () {
    expect(() => View.render('../secret'), throwsA(isA<ViewException>()));
  });
}
