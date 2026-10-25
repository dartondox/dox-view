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
    Route.post('/form', (DoxRequest req) {
      req.session.flashErrors(<String, String>{
        'email': 'The email is taken',
      }, input: req.all());
      return redirect('/form');
    });
  }
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
    View.configure(ViewConfig(path: dir.path, cache: false));
    client = await DoxTestClient.start(
      AppConfig(
        appKey: '4HyiSrq4N5Nfg6bOadIhbFEI8zbUkpxt',
        routers: <Router>[ViewRouter()],
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

  test('View.render gives a string, eg. for mail', () {
    expect(
      View.render('users/show', <String, dynamic>{
        'name': 'Bob',
        'request': <String, String>{'path': '/'},
      }),
      '<h1>Bob</h1><a href="/users/7">/</a>',
    );
  });

  test('a template name can not leave the views folder', () {
    expect(() => View.render('../secret'), throwsA(isA<ViewException>()));
  });
}
