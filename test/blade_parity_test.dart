import 'package:dox_view/dox_view.dart';
import 'package:test/test.dart';

class Post {
  Post(this.title);

  final String title;

  Map<String, dynamic> toJson() => <String, dynamic>{'title': title};
}

class Upper implements ViewDirective {
  @override
  Object? render(List<Object?> args, Scope scope) => '${args[0]}'.toUpperCase();
}

/// what a render gave: the HTML and the warnings
class Result {
  Result(this.html, this.warnings);

  final String html;
  final String warnings;
}

class Harness {
  /// an engine for the template [source] as `main`, with [others]
  static ViewEngine engine(
    String source, {
    Map<String, String> others = const <String, String>{},
    StringSink? sink,
    bool cache = true,
    bool bladeWarnings = true,
    bool bladeOutput = true,
    bool strictVariables = true,
    bool stringZeroIsFalse = true,
    Map<String, ViewDirective> directives = const <String, ViewDirective>{},
  }) => ViewEngine(
    MemoryTemplateLoader(<String, String>{'main': source, ...others}),
    cache: cache,
    warningSink: sink ?? StringBuffer(),
    bladeWarnings: bladeWarnings,
    bladeOutput: bladeOutput,
    strictVariables: strictVariables,
    stringZeroIsFalse: stringZeroIsFalse,
    directives: directives,
  );

  static String render(
    String source, [
    Map<String, Object?> data = const <String, Object?>{},
    Map<String, String> others = const <String, String>{},
  ]) => engine(source, others: others).render('main', data);

  /// render [source] and keep the warnings
  static Result warn(String source, {bool bladeWarnings = true}) {
    StringBuffer sink = StringBuffer();
    String html = engine(
      source,
      sink: sink,
      bladeWarnings: bladeWarnings,
    ).render('main');
    return Result(html, sink.toString());
  }

  static Matcher throwsView(String message, {int line = 1}) => throwsA(
    isA<ViewException>()
        .having((ViewException e) => e.message, 'message', contains(message))
        .having((ViewException e) => e.template, 'template', 'main')
        .having((ViewException e) => e.line, 'line', line),
  );
}

void main() {
  group('Blade name warnings', () {
    test('a Blade name warns with the template, line and the Dox way', () {
      String source =
          'a\n@foreach(\$users as \$user)\n{!! \$user !!}\n@endforeach\n';
      Result result = Harness.warn(source);
      expect(result.html, source);
      expect(
        result.warnings,
        'dox_view: warning: main:3 "{!! !!}" is not Dox syntax. '
        'Use "{{{ value }}}".\n'
        'dox_view: warning: main:2 "@foreach" is not a Dox tag. '
        'Use "@each(item in items) ... @end".\n'
        'dox_view: warning: main:4 "@endforeach" is not a Dox tag. '
        'Use "@end".\n',
      );
    });

    test('every Blade name of the list warns', () {
      for (String tag in <String>[
        '@forelse(x)',
        '@endforelse',
        '@for(x)',
        '@endfor',
        '@while(x)',
        '@endwhile',
        '@switch(x)',
        '@endswitch',
        '@endif',
        '@endunless',
        '@endsection',
        '@stop',
        '@endpush',
        '@endprepend',
        '@endisset',
        '@endempty',
        '@endauth',
        '@endguest',
        '@endenv',
        '@endproduction',
        '@endonce',
        '@endverbatim',
        '@endcomponent',
        '@endslot',
        '@enderror',
        '@php',
        '@endphp',
        '@show',
        '@parent',
      ]) {
        Result result = Harness.warn('x\n$tag\ny');
        expect(result.html, 'x\n$tag\ny', reason: tag);
        expect(
          result.warnings,
          startsWith(
            'dox_view: warning: main:2 "${tag.split('(')[0]}" is not a Dox tag.',
          ),
          reason: tag,
        );
        expect('\n'.allMatches(result.warnings).length, 1, reason: tag);
      }
    });

    test('an end name warns in the middle of a line too', () {
      Result result = Harness.warn('<p class="on @endif">');
      expect(result.warnings, contains('main:1 "@endif" is not a Dox tag'));
    });

    test('the warning comes before the parse error', () {
      StringBuffer sink = StringBuffer();
      ViewEngine engine = Harness.engine('@if(true)\nx\n@endif\n', sink: sink);
      expect(() => engine.render('main'), throwsA(isA<ViewException>()));
      expect(sink.toString(), contains('main:3 "@endif"'));
    });

    test('prose, emails, comments and escaped names do not warn', () {
      for (String text in <String>[
        'mail me@foreach.com or a@endif.com',
        'the @foreach loop and a @foreach (loop) here',
        'ask your @parent (or guardian), then @show it with @php code',
        'a @for (b) and a @while (c) and a @switch (d)',
        '{{-- @foreach(x) {!! y !!} @endif --}}text',
        'a @@foreach(x) b',
        'wow {!! not closed',
        '@verbatim\n{!! x !!}\n@end\n',
        '@media (max-width: 600px) { }',
      ]) {
        expect(Harness.warn(text).warnings, '', reason: text);
      }
    });

    test('a directive of the app with a Blade name does not warn', () {
      StringBuffer sink = StringBuffer();
      ViewEngine engine = Harness.engine(
        '@show(name)\n@show\n',
        sink: sink,
        directives: <String, ViewDirective>{'show': Upper()},
      );
      expect(engine.render('main', <String, Object?>{'name': 'a'}), 'A@show\n');
      expect(sink.toString(), '');
    });

    test('bladeWarnings: false turns them off', () {
      Result result = Harness.warn('@endif {!! x !!}', bladeWarnings: false);
      expect(result.html, '@endif {!! x !!}');
      expect(result.warnings, '');
    });

    test('one warning per template, with the cache on or off', () {
      for (bool cache in <bool>[true, false]) {
        StringBuffer sink = StringBuffer();
        ViewEngine engine = Harness.engine('@endif', sink: sink, cache: cache);
        engine.render('main');
        engine.render('main');
        expect('\n'.allMatches(sink.toString()).length, 1, reason: '$cache');
      }
    });
  });

  group('bladeOutput', () {
    String source =
        '[{{ yes }}][{{ no }}][{{ none }}][{{ ten }}][{{ half }}]'
        '[{{{ yes }}}][{{{ ten }}}][{{ 3 > 2 }}][{{ 1 }}][{{ text }}]';
    Map<String, Object?> data = <String, Object?>{
      'yes': true,
      'no': false,
      'none': null,
      'ten': 10.0,
      'half': 0.5,
      'text': 'true 10.0',
    };

    test('on by default: true is 1, false is empty, 10.0 is 10', () {
      expect(
        ViewEngine(MemoryTemplateLoader(<String, String>{'main': source}))
            .render('main', data),
        '[1][][][10][0.5][1][10][1][1][true 10.0]',
      );
    });

    test('off: true, false and 10.0 print as Dart prints them', () {
      expect(
        Harness.engine(source, bladeOutput: false).render('main', data),
        '[true][false][][10.0][0.5][true][10.0][true][1][true 10.0]',
      );
    });

    test('default: big and special numbers keep their text', () {
      expect(
        Harness.engine('{{ a }} {{ b }} {{ c }}').render(
          'main',
          <String, Object?>{'a': 1e21, 'b': double.nan, 'c': -2.0},
        ),
        '1e+21 NaN -2',
      );
    });

    test('default: @yield, @section and @method print the same way', () {
      expect(
        Harness.engine(
          "@section('a', 2.0)\n@yield('a') @yield('b', true) @method(1.0)",
        ).render('main'),
        '2 1 <input type="hidden" name="_method" value="1">',
      );
    });

    test('default: + still joins text the Dart way', () {
      expect(Harness.engine("{{ 'a' + true }}").render('main'), 'atrue');
    });
  });

  group('@include with data', () {
    Map<String, String> others = <String, String>{
      'card': "<{{ title ?? '' }}|{{ user ?? '' }}|{{ extra ?? '' }}>",
    };

    test('the include sees the parent variables and the data', () {
      expect(
        Harness.render(
          "@include('card', { title: 'Hi', extra: n + 1 })",
          <String, Object?>{'user': 'Ann', 'n': 1},
          others,
        ),
        '<Hi|Ann|2>',
      );
    });

    test('the data wins and does not leak back', () {
      expect(
        Harness.render(
          "@include('card', { user: 'Bob', title: 'T' })"
          "[{{ user }}|{{ title ?? '' }}]",
          <String, Object?>{'user': 'Ann'},
          others,
        ),
        '<T|Bob|>[Ann|]',
      );
    });

    test('@assign in the include does not change the parent', () {
      expect(
        Harness.render(
          "@include('set', { n: 1 })[{{ n }}]",
          <String, Object?>{'n': 0},
          <String, String>{'set': '@assign(n = 5)\n{{ n }}'},
        ),
        '5[0]',
      );
    });

    test('a variable with a map works as the data', () {
      expect(
        Harness.render("@include('card', props)", <String, Object?>{
          'props': <String, Object?>{'title': 'P'},
        }, others),
        '<P||>',
      );
    });

    test('@includeIf and @includeWhen take the condition first', () {
      String source =
          "@includeIf(on, 'card', { title: 'A' })"
          "@includeWhen(on, 'card', { title: 'B' })"
          "@includeWhen(on, 'card')";
      expect(
        Harness.render(source, <String, Object?>{'on': true}, others),
        '<A||><B||><||>',
      );
      expect(
        Harness.render(source, <String, Object?>{'on': false}, others),
        '',
      );
    });

    test('data that is not a map is an error', () {
      for (String source in <String>[
        "\n@include('card', 'x')",
        "\n@include('card', null)",
        "\n@includeIf(true, 'card', 5)",
        "\n@includeWhen(true, 'card', [1])",
      ]) {
        expect(
          () => Harness.render(source, const <String, Object?>{}, others),
          Harness.throwsView('the data of @include must be a map', line: 2),
          reason: source,
        );
      }
    });

    test('too many arguments is an error', () {
      expect(
        () => Harness.render("@include('card', {}, 1)"),
        Harness.throwsView('@include needs 1 to 2 arguments'),
      );
      expect(
        () => Harness.render('@includeWhen(true)'),
        Harness.throwsView('@includeWhen needs 2 to 3 arguments'),
      );
    });
  });

  group(r'$loop', () {
    test('the old fields keep their meaning', () {
      expect(
        Harness.render(
          '@each(x in items)\n'
          '{{ \$loop.index }}{{ \$loop.first }}{{ \$loop.last }}'
          '{{ \$loop.length }} \n@end\n',
          <String, Object?>{
            'items': <String>['a', 'b'],
          },
        ),
        // with bladeOutput, true prints 1 and false prints nothing
        '012 \n112 \n',
      );
    });

    test('iteration, count, remaining, even, odd and depth', () {
      expect(
        Harness.render(
          '@each(x in items)\n'
          '{{ \$loop.iteration }}/{{ \$loop.count }} {{ \$loop.remaining }} '
          '{{ \$loop.even }} {{ \$loop.odd }} {{ \$loop.depth }}'
          '[{{ \$loop.parent }}]\n@end\n',
          <String, Object?>{
            'items': <String>['a', 'b', 'c'],
          },
        ),
        '1/3 2  1 1[]\n2/3 1 1  1[]\n3/3 0  1 1[]\n',
      );
    });

    test('parent is the loop around, also in an include', () {
      expect(
        Harness.render(
          '@each(row in rows)\n@each(cell in row)\n'
          '{{ \$loop.parent.iteration }}.{{ \$loop.iteration }}'
          ':{{ \$loop.depth }} \n@end\n'
          "@include('inner')\n@end\n",
          <String, Object?>{
            'rows': <List<int>>[
              <int>[1, 2],
              <int>[3],
            ],
          },
          <String, String>{
            'inner':
                '@each(x in [1])\n<{{ \$loop.depth }}'
                '{{ \$loop.parent.index }}>\n@end\n',
          },
        ),
        '1.1:2 \n1.2:2 \n<20>\n2.1:2 \n<21>\n',
      );
    });

    test('a loop in a component starts at depth 1', () {
      expect(
        Harness.render(
          "@each(x in [1])\n@!component('c')\n@end\n",
          const <String, Object?>{},
          <String, String>{
            'c': '@each(y in [1])\n{{ \$loop.depth }}{{ \$loop.parent }}\n@end\n',
          },
        ),
        '1\n',
      );
    });

    test('it is still a map: keys, [ ] and @json work', () {
      expect(
        Harness.render(
          '@each(x in [7])\n'
          "{{ \$loop['index'] }} {{ \$loop.keys.length }} @json(\$loop)\n"
          '@end\n',
        ),
        '0 11 {"index":0,"first":true,"last":true,"length":1,"iteration":1,'
        '"count":1,"remaining":0,"even":false,"odd":true,"depth":1,'
        '"parent":null}\n',
      );
    });
  });

  group('@json', () {
    test('prints JSON, with toJson() of objects', () {
      expect(
        Harness.render('@json(data)', <String, Object?>{
          'data': <String, Object?>{
            'n': 1,
            'ok': true,
            'none': null,
            'list': <Object?>[1.5, 'a'],
            'post': Post('Hi'),
          },
        }),
        '{"n":1,"ok":true,"none":null,"list":[1.5,"a"],'
        '"post":{"title":"Hi"}}',
      );
    });

    test('escapes < > & \' and the line separators', () {
      expect(
        Harness.render(
          '<script>const d = @json(text);</script>',
          <String, Object?>{
            'text': '</script><b a=\'1\'>&amp; "q" \u2028\u2029',
          },
        ),
        r'<script>const d = "\u003C/script\u003E\u003Cb a=\u00271\u0027'
        r'\u003E\u0026amp; \"q\" \u2028\u2029";</script>',
      );
    });

    test('json() gives the same text, not escaped again', () {
      Map<String, Object?> data = <String, Object?>{
        'v': <String, Object?>{'a': '<b>', 'q': "it's"},
      };
      String tag = Harness.render('@json(v)', data);
      expect(tag, r'{"a":"\u003Cb\u003E","q":"it\u0027s"}');
      expect(Harness.render('{{ json(v) }}', data), tag);
      expect(Harness.render('{{{ json(v) }}}', data), tag);
      expect(SafeString.json(data['v']).value, tag);
    });

    test('a map literal and text work', () {
      expect(
        Harness.render(
          "@json({ a: [1, 2] }) @json('x') @json(none)",
          <String, Object?>{'none': null},
        ),
        '{"a":[1,2]} "x" null',
      );
    });

    test('a value that can not be JSON is an error', () {
      expect(
        () => Harness.render('\n@json(v)', <String, Object?>{'v': Object()}),
        Harness.throwsView('@json can not make JSON of Object', line: 2),
      );
      expect(
        () => Harness.render('\n\n{{ json(v) }}', <String, Object?>{
          'v': DateTime(2026),
        }),
        Harness.throwsView('can not make JSON of DateTime', line: 3),
      );
    });

    test('prose stays text', () {
      for (String text in <String>[
        'the @json (format) is',
        'send @json to the page',
        '@json (data)\n',
        'me@json(x)',
      ]) {
        expect(Harness.render(text), text, reason: text);
      }
    });

    test('a json value in the data wins over the helper', () {
      expect(
        Harness.render('{{ json }}', <String, Object?>{'json': 'mine'}),
        'mine',
      );
    });
  });

  group('@error', () {
    String source = "@error('email')\n<p>{{ message }}</p>\n@end\n";

    test('shows the message of the field', () {
      expect(
        Harness.render(source, <String, Object?>{
          'errors': <String, Object?>{'email': 'The email is taken'},
        }),
        '<p>The email is taken</p>\n',
      );
    });

    test('a list gives its first message', () {
      expect(
        Harness.render(source, <String, Object?>{
          'errors': <String, Object?>{
            'email': <String>['First', 'Second'],
          },
        }),
        '<p>First</p>\n',
      );
    });

    test('no error for the field prints nothing', () {
      for (Object? errors in <Object?>[
        <String, Object?>{},
        <String, Object?>{'name': 'x'},
        <String, Object?>{'email': ''},
        <String, Object?>{'email': <String>[]},
        <String, Object?>{'email': null},
        <String, Object?>{
          'email': <String, Object?>{'a': 'b'},
        },
        null,
        'text',
      ]) {
        expect(
          Harness.render(source, <String, Object?>{'errors': errors}),
          '',
          reason: '$errors',
        );
      }
      // no `errors` at all
      expect(Harness.render(source), '');
    });

    test('a name with dots: the flat key first, then nested maps', () {
      String nested = "@error('user.email')\n{{ message }}\n@end\n";
      expect(
        Harness.render(nested, <String, Object?>{
          'errors': <String, Object?>{'user.email': 'flat'},
        }),
        'flat\n',
      );
      expect(
        Harness.render(nested, <String, Object?>{
          'errors': <String, Object?>{
            'user': <String, Object?>{'email': 'nested'},
          },
        }),
        'nested\n',
      );
      expect(
        Harness.render(nested, <String, Object?>{
          'errors': <String, Object?>{'user': 'text'},
        }),
        '',
      );
    });

    test('@else shows when there is no error', () {
      String withElse = "@error('email')\nbad\n@else\nok\n@end\n";
      expect(Harness.render(withElse), 'ok\n');
      expect(
        Harness.render(withElse, <String, Object?>{
          'errors': <String, Object?>{'email': 'x'},
        }),
        'bad\n',
      );
    });

    test('message is only inside the block, and it is escaped', () {
      expect(
        Harness.render(
          "{{ message }}@error('a'){{ message }}@end{{ message }}",
          <String, Object?>{
            'message': 'outer',
            'errors': <String, Object?>{'a': '<b>'},
          },
        ),
        'outer&lt;b&gt;outer',
      );
    });

    test('the field can be a variable, eg. in a component', () {
      expect(
        Harness.render(
          "@!input({ name: 'email' })",
          <String, Object?>{},
          <String, String>{
            'components/input':
                '@error(name)\n{{ name }}: {{ message }}\n@end\n',
          },
        ),
        '',
      );
      ViewEngine engine = Harness.engine(
        "@!input({ name: 'email' })",
        others: <String, String>{
          'components/input': '@error(name)\n{{ name }}: {{ message }}\n@end\n',
        },
      );
      expect(
        engine.render('main', const <String, Object?>{}, <String, Object?>{
          'errors': <String, Object?>{'email': 'bad'},
        }),
        'email: bad\n',
      );
    });

    test('prose stays text', () {
      for (String text in <String>[
        'an @error (see log) here',
        'an @error in the log',
        '@error (404)\n',
        'me@error(x)',
      ]) {
        expect(Harness.render(text), text, reason: text);
      }
    });

    test('with a space before ( and a quoted name, it is a tag', () {
      expect(
        Harness.render("a @error ('x') b @end c", <String, Object?>{
          'errors': <String, Object?>{'x': 'y'},
        }),
        'a  b  c',
      );
    });

    test('a missing @end is an error', () {
      expect(
        () => Harness.render("@error('email')\nx"),
        Harness.throwsView('@error has no @end'),
      );
    });
  });

  group('new tag names', () {
    test('with no ( ) they stay text', () {
      String text = 'use @includeWhen or @json and @error here. @json';
      expect(Harness.render(text), text);
    });

    test('a component with the same name wins', () {
      expect(
        Harness.render(
          '@!json({ a: 1 })|@error({ a: 2 })x @end|@!includeWhen({ a: 3 })',
          const <String, Object?>{},
          <String, String>{
            'components/json': 'J{{ a }}',
            'components/error': 'E{{ a }}{{ \$slot }}',
            'components/includeWhen': 'I{{ a }}',
          },
        ),
        'J1|E2x |I3',
      );
    });

    test('a directive can not use the name (isBuiltIn)', () {
      for (String name in <String>['includeWhen', 'json', 'error']) {
        expect(
          () => Harness.engine('').directive(name, Upper()),
          throwsA(isA<ViewException>()),
          reason: name,
        );
      }
    });
  });

  group('strictVariables', () {
    test('off: a missing variable prints nothing', () {
      expect(
        Harness.engine(
          '[{{ missing }}]@if(missing) x @end',
          strictVariables: false,
        ).render('main'),
        '[]',
      );
    });

    test('on by default: a missing variable is an error', () {
      expect(
        () => ViewEngine(
          const MemoryTemplateLoader(<String, String>{'main': '{{ missing }}'}),
        ).render('main'),
        Harness.throwsView('the variable "missing" is not defined'),
      );
    });

    test('default: a missing variable is an error with its name', () {
      for (String source in <String>[
        '\n{{ missing }}',
        '\n@if(missing) x @end',
        '\n{{ missing.name }}',
        '\n{{ missing ? 1 : 2 }}',
        '\n@include(missing)',
        '\n@each(x in missing)\n@end',
      ]) {
        expect(
          () => Harness.engine(source).render('main'),
          Harness.throwsView('the variable "missing" is not defined', line: 2),
          reason: source,
        );
      }
    });

    test('default: a variable with a null value is fine', () {
      expect(
        Harness.engine('[{{ none }}]')
            .render('main', <String, Object?>{'none': null}),
        '[]',
      );
    });

    test('default: @isset, @empty, ?? and ?. do not throw', () {
      expect(
        Harness.engine(
          '@isset(missing)\nA\n@else\nB\n@end\n'
          '@empty(missing)\nC\n@end\n'
          "{{ missing ?? 'D' }} {{ missing ?? other ?? 'E' }} "
          '[{{ missing?.name }}] [{{ missing?.trim() }}] '
          "{{ missing?.a?.b ?? 'F' }}",
        ).render('main'),
        'B\nC\nD E [] [] F',
      );
    });

    test('default: the right side of ?? and a field after ?? still throw', () {
      for (String source in <String>[
        '{{ none ?? missing }}',
        '{{ (missing ?? none).name }}',
      ]) {
        expect(
          () =>
              Harness.engine(source)
                  .render('main', <String, Object?>{'none': null}),
          throwsA(isA<ViewException>()),
          reason: source,
        );
      }
    });

    test('default: @error with no errors prints nothing', () {
      expect(
        Harness.engine("[@error('email')\n{{ message }}\n@end\n]")
            .render('main'),
        '[]',
      );
    });

    test('default: components, includes, loops and globals work', () {
      expect(
        Harness.engine(
          '@each(x in [1])\n{{ \$loop.index }}{{ x }}\n@end\n'
          "@include('inc', { a: 1 })\n@!component('comp', { b: 2 })\n"
          '{{ json(1) }}',
          others: <String, String>{'inc': '{{ a }}', 'comp': '{{ b }}'},
        ).render('main'),
        '01\n121',
      );
      expect(
        () => Harness.engine(
          "@!component('comp')",
          others: <String, String>{'comp': '\n{{ pageVar }}'},
        ).render('main', <String, Object?>{'pageVar': 1}),
        throwsA(
          isA<ViewException>()
              .having((ViewException e) => e.template, 'template', 'comp')
              .having((ViewException e) => e.line, 'line', 2),
        ),
      );
    });
  });

  group('stringZeroIsFalse', () {
    String source =
        "@if(zero) a @end|@unless(zero) b @end|{{ zero ? 'c' : 'd' }}|"
        "{{ zero || 'e' }}|{{ zero && 'f' }}|{{ !zero }}|"
        '@empty(zero) g @end|<i @class({ on: zero }) @checked(zero)>';
    Map<String, Object?> data = <String, Object?>{'zero': '0'};

    test("off: '0' is true", () {
      expect(
        Harness.engine(
          source,
          bladeOutput: false,
          stringZeroIsFalse: false,
        ).render('main', data),
        ' a ||c|0|f|false||<i class="on" checked>',
      );
    });

    test("on by default: '0' is false", () {
      expect(
        ViewEngine(MemoryTemplateLoader(<String, String>{'main': source}))
            .render('main', data),
        '| b |d|e|0|1| g |<i class="" >',
      );
    });

    test('default: other text and the number 0 are as before', () {
      expect(
        Harness.engine(
          "@if('0.0') a @end|@if('00') b @end|@if(' ') c @end|@if(0) d @end|"
          "@if('') e @end|@includeIf('0', 'x')",
          others: <String, String>{'x': 'X'},
        ).render('main'),
        ' a | b | c |||',
      );
    });
  });

  group('Scope defaults', () {
    test('Scope() has the new defaults', () {
      Scope scope = Scope(<String, Object?>{});
      expect(scope.strictVariables, isTrue);
      expect(scope.stringZeroIsFalse, isTrue);
    });

    test('Scope.root() has the new defaults', () {
      Scope scope = Scope.root(<String, Object?>{});
      expect(scope.strictVariables, isTrue);
      expect(scope.stringZeroIsFalse, isTrue);
    });
  });

  group('the options of an engine', () {
    test('two engines with the same templates do not share them', () {
      MemoryTemplateLoader loader = MemoryTemplateLoader(<String, String>{
        'main': "[{{ on }}]@if('0') x @end",
      });
      ViewEngine plain = ViewEngine(
        loader,
        bladeOutput: false,
        strictVariables: false,
        stringZeroIsFalse: false,
      );
      ViewEngine blade = ViewEngine(loader);
      Map<String, Object?> data = <String, Object?>{'on': true};
      for (int round = 0; round < 2; round++) {
        expect(plain.render('main', data), '[true] x ');
        expect(blade.render('main', data), '[1]');
      }
      expect(plain.bladeOutput, isFalse);
      expect(plain.strictVariables, isFalse);
      expect(plain.stringZeroIsFalse, isFalse);
      expect(blade.bladeOutput, isTrue);
      expect(blade.strictVariables, isTrue);
      expect(blade.stringZeroIsFalse, isTrue);
    });
  });
}
