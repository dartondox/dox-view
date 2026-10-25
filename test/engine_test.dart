import 'package:dox_view/dox_view.dart';
import 'package:test/test.dart';

class User {
  User(this.name, this.admin);

  final String name;
  final bool admin;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'admin': admin,
  };
}

/// render the template [source] with [data]. [others] are more
/// templates it can include.
String render(
  String source, [
  Map<String, Object?> data = const <String, Object?>{},
  Map<String, String> others = const <String, String>{},
]) {
  ViewEngine engine = ViewEngine(
    MemoryTemplateLoader(<String, String>{'main': source, ...others}),
  );
  return engine.render('main', data);
}

void main() {
  group('output', () {
    test('escapes {{ }}', () {
      expect(
        render('<p>{{ text }}</p>', <String, Object?>{
          'text': '<b>"Tom" & \'Ann\'</b>',
        }),
        '<p>&lt;b&gt;&quot;Tom&quot; &amp; &#39;Ann&#39;&lt;/b&gt;</p>',
      );
    });

    test('does not escape {{{ }}} and SafeString', () {
      expect(
        render('{{{ html }}} {{ safe }}', <String, Object?>{
          'html': '<b>x</b>',
          'safe': const SafeString('<i>y</i>'),
        }),
        '<b>x</b> <i>y</i>',
      );
    });

    test('null and a missing variable print nothing', () {
      expect(render('[{{ nothing }}][{{ missing }}]'), '[][]');
    });

    test('comments and escaped tags', () {
      expect(
        render('a{{-- hidden {{ x }} --}}b @{{ name }} @@if me@mail.com'),
        'ab {{ name }} @if me@mail.com',
      );
    });

    test('unknown tags like @media stay text', () {
      expect(
        render('@media (max-width: 600px) { a { color: red } }'),
        '@media (max-width: 600px) { a { color: red } }',
      );
    });
  });

  group('expressions', () {
    Map<String, Object?> data = <String, Object?>{
      'user': User('Ann', true),
      'items': <int>[1, 2, 3],
      'map': <String, Object?>{'a': 1, 'b space': 2},
      'price': 9.5,
      'name': 'dox',
      'add': (int a, int b) => a + b,
    };

    test('math, compare and logic', () {
      expect(
        render(
          '{{ 1 + 2 * 3 }} {{ (1 + 2) * 3 }} {{ 7 % 4 }} {{ 7 ~/ 2 }} '
          '{{ 2 > 1 && 1 >= 1 }} {{ !true || false }} {{ 1 === 1.0 }}',
        ),
        '7 9 3 3 true false true',
      );
    });

    test('members, index, ternary and ??', () {
      expect(
        render(
          '{{ user.name }} {{ items[1] }} {{ map["b space"] }} '
          '{{ user.admin ? "admin" : "user" }} {{ missing ?? "none" }} '
          '{{ missing?.name }} {{ items.length }} {{ items.last }}',
          data,
        ),
        'Ann 2 2 admin none  3 3',
      );
    });

    test('functions and methods', () {
      expect(
        render(
          '{{ add(2, 3) }} {{ name.toUpperCase() }} {{ items.join("-") }} '
          '{{ price.toStringAsFixed(2) }} {{ "a,b".split(",").length }} '
          '{{ items.contains(2) }}',
          data,
        ),
        '5 DOX 1-2-3 9.50 2 true',
      );
    });

    test('strings join with +', () {
      expect(render("{{ 'Hi ' + name + '!' }}", data), 'Hi dox!');
    });

    test('lists and maps', () {
      expect(render("{{ [1, 2].length }} {{ { a: 1, 'b': 2 }.b }}"), '2 2');
    });
  });

  group('@if', () {
    String template =
        '@if(n > 10)\nbig\n@elseif(n > 5)\nmid\n@else\nsmall\n@end\n';

    test('picks the branch, and leaves no empty lines', () {
      expect(render(template, <String, Object?>{'n': 20}), 'big\n');
      expect(render(template, <String, Object?>{'n': 7}), 'mid\n');
      expect(render(template, <String, Object?>{'n': 1}), 'small\n');
    });

    test('empty values are false', () {
      expect(
        render(
          '@if(a) A @end@if(b) B @end@if(c) C @end@if(d) D @end@if(e) E @end',
          <String, Object?>{
            'a': '',
            'b': <int>[],
            'c': 0,
            'd': <String, int>{},
            'e': 'yes',
          },
        ),
        ' E ',
      );
    });

    test('@unless', () {
      expect(
        render('@unless(x) no @else yes @end', <String, Object?>{}),
        ' no ',
      );
    });

    test('inline in a line keeps the text around it', () {
      expect(
        render('<li class="@if(on) active @end">x</li>', <String, Object?>{
          'on': true,
        }),
        '<li class=" active ">x</li>',
      );
    });
  });

  group('@each', () {
    test('a list with index and \$loop', () {
      expect(
        render(
          '@each((item, i) in items)\n'
          '{{ i }}:{{ item }}{{ \$loop.last ? "" : "," }}\n'
          '@end\n',
          <String, Object?>{
            'items': <String>['a', 'b'],
          },
        ),
        '0:a,\n1:b\n',
      );
    });

    test('a map gives value and key', () {
      expect(
        render('@each((v, k) in m){{ k }}={{ v }};@end', <String, Object?>{
          'm': <String, int>{'x': 1, 'y': 2},
        }),
        'x=1;y=2;',
      );
    });

    test('@else for an empty list', () {
      expect(
        render(
          '@each(u in users)\n{{ u }}\n@else\nNo users\n@end\n',
          <String, Object?>{'users': <String>[]},
        ),
        'No users\n',
      );
    });

    test('objects with toJson', () {
      expect(
        render('@each(u in users){{ u.name }} @end', <String, Object?>{
          'users': <User>[User('Ann', true), User('Bob', false)],
        }),
        'Ann Bob ',
      );
    });
  });

  group('@let and @assign', () {
    test('make and change a variable', () {
      expect(
        render(
          '@let(total = 0)\n'
          '@each(n in nums)\n'
          '@assign(total = total + n)\n'
          '@end\n'
          '{{ total }}',
          <String, Object?>{
            'nums': <int>[1, 2, 3],
          },
        ),
        '6',
      );
    });
  });

  group('@include', () {
    test('sees the variables of the parent', () {
      expect(
        render(
          "<nav>@include('partials/nav')</nav>",
          <String, Object?>{'name': 'Ann'},
          <String, String>{'partials/nav': 'Hi {{ name }}'},
        ),
        '<nav>Hi Ann</nav>',
      );
    });

    test('@includeIf', () {
      expect(
        render(
          "@includeIf(show, 'x')@includeIf(!show, 'x')",
          <String, Object?>{'show': true},
          <String, String>{'x': 'X'},
        ),
        'X',
      );
    });
  });

  group('components', () {
    Map<String, String> templates = <String, String>{
      'layouts/main':
          '<title>{{ \$slots.title }}</title>'
          '<main>{{ \$slots.main }}</main>',
      'components/button': '<button class="{{ type ?? \'default\' }}">{{ \$slots.main }}</button>',
      'components/form/input': '<input name="{{ name }}">',
    };

    test('a layout with slots', () {
      expect(
        render(
          "@component('layouts/main')\n"
          "@slot('title')\n"
          'Home\n'
          '@end\n'
          '<h1>Hi {{ name }}</h1>\n'
          '@end\n',
          <String, Object?>{'name': '<Ann>'},
          templates,
        ),
        '<title>Home\n</title><main><h1>Hi &lt;Ann&gt;</h1>\n</main>',
      );
    });

    test('a component as a tag, with props', () {
      expect(
        render(
          "@button({ type: 'primary' }) Save @end @!form.input({ name: 'email' })",
          <String, Object?>{},
          templates,
        ),
        '<button class="primary"> Save </button> <input name="email">',
      );
    });

    test('props are variables and \$props', () {
      expect(
        render(
          "@!component('card', { title: 'Hi' })",
          <String, Object?>{},
          <String, String>{
            'card': "{{ title }} {{ \$props.title }} {{ other ?? 'none' }}",
          },
        ),
        'Hi Hi none',
      );
    });

    test('a component does not see the variables of the caller', () {
      expect(
        render("@!component('components/form/input')", <String, Object?>{
          'name': 'leak',
        }, templates),
        '<input name="">',
      );
    });
  });

  group('globals', () {
    test('every template can use them', () {
      ViewEngine engine = ViewEngine(
        const MemoryTemplateLoader(<String, String>{
          'a': '{{ app }} {{ twice(2) }}',
        }),
        globals: <String, Object?>{'app': 'Dox'},
      );
      engine.global('twice', (int n) => n * 2);
      expect(engine.render('a'), 'Dox 4');
    });
  });

  group('errors', () {
    test('name the template and the line', () {
      expect(
        () => render('a\nb\n{{ 1 + }}'),
        throwsA(
          isA<ViewException>()
              .having((ViewException e) => e.template, 'template', 'main')
              .having((ViewException e) => e.line, 'line', 3),
        ),
      );
    });

    test('an error in an include names the include', () {
      expect(
        () => render("@include('bad')", <String, Object?>{}, <String, String>{
          'bad': '\n{{ user.name }}',
        }),
        throwsA(
          isA<ViewException>()
              .having((ViewException e) => e.template, 'template', 'bad')
              .having((ViewException e) => e.line, 'line', 2),
        ),
      );
    });

    test('a missing @end', () {
      expect(
        () => render('@if(true)\nx'),
        throwsA(
          isA<ViewException>().having(
            (ViewException e) => e.message,
            'message',
            '@if has no @end',
          ),
        ),
      );
    });

    test('a missing template', () {
      expect(() => render("@include('nope')"), throwsA(isA<ViewException>()));
    });

    test('a template that includes itself', () {
      expect(() => render("@include('main')"), throwsA(isA<ViewException>()));
    });
  });
}
