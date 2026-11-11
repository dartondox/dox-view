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

/// an object that can change, and counts its toJson() calls
class Counter {
  int value = 0;
  int calls = 0;

  Map<String, dynamic> toJson() {
    calls++;
    return <String, dynamic>{'value': value};
  }
}

class Shout implements ViewDirective {
  @override
  Object? render(List<Object?> args, Scope scope) =>
      '${args[0]}'.toUpperCase() + '!' * (args[1]! as int);
}

class Bold implements ViewDirective {
  @override
  Object? render(List<Object?> args, Scope scope) =>
      SafeString('<b>${escapeHtml('${args[0]}')}</b>');
}

/// reads a variable of the template
class Hello implements ViewDirective {
  @override
  Object? render(List<Object?> args, Scope scope) =>
      'Hello ${scope.lookup('name')}';
}

class Fail implements ViewDirective {
  @override
  Object? render(List<Object?> args, Scope scope) => throw StateError('no');
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

    test('null prints nothing, a missing variable is an error', () {
      expect(
        render('[{{ nothing }}]', <String, Object?>{'nothing': null}),
        '[]',
      );
      expect(() => render('[{{ missing }}]'), throwsA(isA<ViewException>()));
    });

    test('true prints 1, false prints nothing, 10.0 prints 10', () {
      expect(
        render('[{{ yes }}][{{ no }}][{{ ten }}]', <String, Object?>{
          'yes': true,
          'no': false,
          'ten': 10.0,
        }),
        '[1][][10]',
      );
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
        '7 9 3 3 1  1',
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
        '5 DOX 1-2-3 9.50 2 1',
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
        render('@unless(x) no @else yes @end', <String, Object?>{'x': false}),
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

    test('a change to an object between renders shows', () {
      ViewEngine engine = ViewEngine(
        MemoryTemplateLoader(<String, String>{'main': '{{ counter.value }}'}),
      );
      Counter counter = Counter();
      engine.global('counter', counter);
      expect(engine.render('main'), '0');
      counter.value = 5;
      expect(engine.render('main'), '5');
    });

    test('toJson() runs once per object in one render', () {
      Counter counter = Counter();
      expect(
        render('{{ c.value }}{{ c.value }}{{ c.value }}', <String, Object?>{
          'c': counter,
        }),
        '000',
      );
      expect(counter.calls, 1);
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

    test('shared data reaches components, page data does not', () {
      ViewEngine engine = ViewEngine(
        const MemoryTemplateLoader(<String, String>{
          'page': "@component('layout')@end",
          'layout': "{{ user }}|{{ secret ?? 'none' }}",
        }),
      );
      expect(
        engine.render(
          'page',
          <String, Object?>{'secret': 'x'},
          <String, Object?>{'user': 'Ann'},
        ),
        'Ann|none',
      );
    });

    test('a component does not see the variables of the caller', () {
      // the component reads name, which only the caller has
      expect(
        () => render("@!component('components/form/input')", <String, Object?>{
          'name': 'leak',
        }, templates),
        throwsA(
          isA<ViewException>().having(
            (ViewException e) => e.message,
            'message',
            contains('"name" is not defined'),
          ),
        ),
      );
    });
  });

  group('Blade tags', () {
    test('@isset and @empty, with @else', () {
      String template =
          '@isset(user.name)set @else not @end '
          '@empty(items)empty @else full @end';
      expect(
        render(template, <String, Object?>{
          'user': <String, Object?>{'name': 'Ann'},
          'items': <int>[1],
        }),
        'set   full ',
      );
      // a field of null is not an error here
      expect(render(template), ' not  empty ');
    });

    test('in text, @empty (x) and @class (see docs) stay text', () {
      expect(
        render('Lists show @empty (none) and @class (see docs).'),
        'Lists show @empty (none) and @class (see docs).',
      );
      expect(render('a @isset (b) c @env (d) e'), 'a @isset (b) c @env (d) e');
      // with a space and an @end after it, it works like on 3.1.0
      Map<String, Object?> data = <String, Object?>{'x': 1, 'list': <int>[]};
      expect(render('<p>@isset (x) hi @end</p>', data), '<p> hi </p>');
      expect(render('a @empty (list) none @end b', data), 'a  none  b');
      expect(render('<b>@isset (x)\nhi\n@end</b>', data), '<b>\nhi\n</b>');
      // a block inside it has its own @end
      expect(render('a @isset (x) @if(true) y @end z @end', data), 'a   y  z ');
      // with no space, or alone on its line, it is still a tag
      expect(render('@empty (x)\nnone\n@end\n'), 'none\n');
      expect(
        () => render('a @class(see docs) b'),
        throwsA(isA<ViewException>()),
      );
    });

    test(
      '@empty (none) alone on its line, with no @end of its own, is text',
      () {
        expect(render('@empty (none)\n'), '@empty (none)\n');
        expect(
          render('Items:\n@isset (see below)\n'),
          'Items:\n@isset (see below)\n',
        );
        // the @end of the block around it is not its own
        Map<String, Object?> data = <String, Object?>{
          'items': <int>[1],
        };
        expect(
          render('@each(i in items)\n{{ i }}\n@empty (none)\n@end\n', data),
          '1\n@empty (none)\n',
        );
        expect(render('@if(true)\n@empty (x)\nnone\n@end\n@end\n'), 'none\n');
        // a tag in the middle of a line also skips the @end around it
        expect(
          render('@if(true)\na @empty (none) b\n@end\n'),
          'a @empty (none) b\n',
        );
      },
    );

    test('many nested tags with a space before ( parse fast', () {
      // each tag used to scan all the tags after it, again for each
      // tag inside it: 2 more levels took 4 times as long. 24 levels
      // took about 6 seconds, and now take a few milliseconds. The
      // parse does not wait, so a test timeout can not stop it: keep
      // the level count low enough for the old code to end.
      int levels = 24;
      String source = 'a ${'@isset (x) ' * levels}y${' @end' * levels} b';
      Stopwatch watch = Stopwatch()..start();
      expect(
        render(source, <String, Object?>{'x': 1}),
        'a ${' ' * levels}y${' ' * levels} b',
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('spaces after the last tag at the end of the file are removed', () {
      expect(render('@if(true)\nyes\n@end   '), 'yes\n');
      expect(render('@if(true)\nyes\n@end  \n'), 'yes\n');
      // not alone on its line: the spaces stay
      expect(render('a @if(true) b @end  '), 'a  b   ');
    });

    test('with no ( ), @empty and @class stay text', () {
      expect(render('a @empty b @class c'), 'a @empty b @class c');
    });

    test('@auth and @guest read the shared \$auth, not the data', () {
      String template = '@auth\nin\n@else\nout\n@end\n@guest\nguest\n@end\n';
      String renderWith(Map<String, Object?> data, bool loggedIn) =>
          ViewEngine(MemoryTemplateLoader(<String, String>{'main': template}))
              .render('main', data, <String, Object?>{r'$auth': loggedIn});

      expect(renderWith(<String, Object?>{}, true), 'in\n');
      expect(renderWith(<String, Object?>{}, false), 'out\nguest\n');
      // the view data can not log a user in
      expect(
        renderWith(<String, Object?>{r'$auth': true}, false),
        'out\nguest\n',
      );
      expect(render('@auth\nin\n@end\n'), '');
      expect(
        () => render("@auth('admin')\nx\n@end"),
        throwsA(isA<ViewException>()),
      );
    });

    test('bare words in text stay text', () {
      for (String text in <String>[
        '<p>@once upon a time</p>',
        '<p>We are @production-ready.</p>',
        '<p>@guest-list</p>',
        '<p>follow @guest on X</p>',
        '<p>@auth is on</p>',
      ]) {
        expect(render(text), text);
      }
      // @verbatim in text does not eat the tags up to a later @end
      expect(
        render(
          '<code>@verbatim</code>\n@if(on)\n{{ name }}\n@end\n',
          <String, Object?>{'on': true, 'name': 'Ann'},
        ),
        '<code>@verbatim</code>\nAnn\n',
      );
    });

    test('@env and @production', () {
      String renderIn(String environment, String source) => ViewEngine(
        MemoryTemplateLoader(<String, String>{'main': source}),
        environment: environment,
      ).render('main');

      String template =
          "@env('local')L @end @env(['staging', 'production'])S @end\n"
          '@production\nP\n@else\nN\n@end\n';
      expect(renderIn('local', template), 'L  \nN\n');
      expect(renderIn('production', template), ' S \nP\n');
      // case does not matter, like the cache default
      expect(renderIn('Production', template), ' S \nP\n');
      expect(renderIn('LOCAL', template), 'L  \nN\n');
    });

    test('@class escapes the names', () {
      expect(
        render(
          "<a @class(['btn', { active: on, off: !on }, bad])>",
          <String, Object?>{'on': true, 'bad': '"><script>'},
        ),
        '<a class="btn active &quot;&gt;&lt;script&gt;">',
      );
    });

    test('@checked, @selected and @disabled', () {
      expect(
        render(
          '<input @checked(a)><option @selected(b)><button @disabled(a)>',
          <String, Object?>{'a': true, 'b': false},
        ),
        '<input checked><option ><button disabled>',
      );
    });

    test('@verbatim does not run anything inside', () {
      expect(
        render(
          '@verbatim\n{{ name }} @if(x) {{{ x }}} {{ \n@end\n{{ name }}',
          <String, Object?>{'name': 'Ann'},
        ),
        '{{ name }} @if(x) {{{ x }}} {{ \nAnn',
      );
      expect(() => render('@verbatim\n{{ x }}'), throwsA(isA<ViewException>()));
    });

    test('@once shows once in one render, in each render', () {
      ViewEngine engine = ViewEngine(
        const MemoryTemplateLoader(<String, String>{
          'main': '@!box() @!box() @!box()',
          'components/box': '[\n@once\n<script>\n@end\n]',
        }),
        cache: false,
      );
      expect(engine.render('main'), '[\n<script>\n] [\n] [\n]');
      expect(engine.render('main'), '[\n<script>\n] [\n] [\n]');
    });

    test('a component with the same name wins', () {
      expect(
        render('@!class({ a: 1 })', <String, Object?>{}, <String, String>{
          'components/class': 'component {{ a }}',
        }),
        'component 1',
      );
    });
  });

  group('component attributes and slots', () {
    Map<String, String> templates = <String, String>{
      'components/button':
          "<button {{ \$attributes.merge({ class: 'btn', type: 'button' }) }}>"
          '{{ \$slot }}|{{ \$slots.main }}</button>',
      'components/attrs': '<i {{ \$attributes }}>{{ \$attributes.id }}</i>',
      'components/check': '@if(\$slots.main)full @else empty @end',
    };

    test('merge joins class, a prop wins, and values are escaped', () {
      expect(
        render(
          "@!button({ class: 'big', type: 'submit', title: t })",
          <String, Object?>{'t': '"x"'},
          templates,
        ),
        '<button class="btn big" type="submit" title="&quot;x&quot;">'
        '|</button>',
      );
    });

    test('\$attributes.except leaves out logic props', () {
      expect(
        render(
          "@!attrs({ id: 'a', variant: 'big', size: 2 })",
          <String, Object?>{},
          <String, String>{
            'components/attrs':
                "<i {{ \$attributes.except(['variant', 'size']).merge({ class: 'x' }) }}>"
                '{{ \$attributes.except(\'id\') }}</i>',
          },
        ),
        '<i class="x" id="a">variant="big" size="2"</i>',
      );
    });

    test('\$attributes prints text, numbers and true only', () {
      expect(
        render(
          "@!attrs({ id: 'a', n: 2, hidden: true, off: false, list: [1], "
          "'bad\"name': 1 })",
          <String, Object?>{},
          templates,
        ),
        '<i id="a" n="2" hidden>a</i>',
      );
    });

    test('\$attributes prints numbers like {{ }} with bladeOutput', () {
      const String source = '@!attrs({ a: 1.0, b: 0.5, c: 3, d: true })';
      Map<String, String> others = <String, String>{
        'components/attrs':
            '<i {{ \$attributes }}|{{ \$attributes.merge({ e: 2.0 }) }}|'
            '{{ \$attributes.except([\'d\']) }}></i>',
      };
      String run(bool blade) => ViewEngine(
        MemoryTemplateLoader(<String, String>{'main': source, ...others}),
        bladeOutput: blade,
      ).render('main');
      expect(
        run(true),
        '<i a="1" b="0.5" c="3" d|e="2" a="1" b="0.5" c="3" d|'
        'a="1" b="0.5" c="3"></i>',
      );
      expect(
        run(false),
        '<i a="1.0" b="0.5" c="3" d|e="2.0" a="1.0" b="0.5" c="3" d|'
        'a="1.0" b="0.5" c="3"></i>',
      );
    });

    test('\$slot and \$slots.main are empty text when the slot is empty', () {
      expect(
        render('@!button()', <String, Object?>{}, templates),
        '<button class="btn" type="button">|</button>',
      );
      expect(
        render('@check() @end', <String, Object?>{}, templates),
        ' empty ',
      );
      expect(
        render('@check() x @end', <String, Object?>{}, templates),
        'full ',
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

  group('layouts', () {
    Map<String, String> templates = <String, String>{
      'layouts/app':
          "<title>@yield('title', 'My <app>')</title>\n"
          '<main>\n'
          "@yield('content')\n"
          "</main>@yield('nothing')",
    };

    test('a page fills the sections of its layout', () {
      expect(
        render(
          "@extends('layouts/app')\n"
          "@section('title', name)\n"
          "@section('content')\n"
          '<p>Hi {{ name }}</p>\n'
          '@end\n',
          <String, Object?>{'name': '<Ann>'},
          templates,
        ),
        '<title>&lt;Ann&gt;</title>\n'
        '<main>\n'
        '<p>Hi &lt;Ann&gt;</p>\n'
        '</main>',
      );
    });

    test('@yield prints its default, escaped', () {
      expect(
        render("@extends('layouts/app')", <String, Object?>{}, templates),
        '<title>My &lt;app&gt;</title>\n<main>\n</main>',
      );
    });

    test('text outside a section is dropped, but @let and @push work', () {
      expect(
        render(
          '{{-- a comment can come first --}}\n'
          "@extends('base')\n"
          'dropped {{ name }}\n'
          "@let(greeting = 'Hello')\n"
          "@push('js')\n"
          'a.js\n'
          '@end\n'
          "@section('content')\n"
          '{{ greeting }} {{ name }}\n'
          '@end\n',
          <String, Object?>{'name': 'Ann'},
          <String, String>{'base': "[@yield('content')][@stack('js')]"},
        ),
        '[Hello Ann\n][a.js\n]',
      );
    });

    test('the layout sees the data of the page', () {
      expect(
        render(
          "@extends('base')",
          <String, Object?>{'name': 'Ann'},
          <String, String>{'base': 'Hi {{ name }}'},
        ),
        'Hi Ann',
      );
    });

    test('a layout can extend a layout, and the page wins', () {
      expect(
        render(
          "@extends('admin')\n"
          "@section('title', 'Users')\n"
          "@section('page')\n"
          'list\n'
          '@end\n',
          <String, Object?>{},
          <String, String>{
            'admin':
                "@extends('base')\n"
                "@section('title', 'Admin')\n"
                "@section('content')\n"
                "<nav></nav>@yield('page')"
                '@end\n',
            'base': "<title>@yield('title')</title>@yield('content')",
          },
        ),
        '<title>Users</title><nav></nav>list\n',
      );
    });

    test('the layout name can be an expression', () {
      expect(
        render(
          '@extends(layout)',
          <String, Object?>{'layout': 'base'},
          <String, String>{'base': 'base'},
        ),
        'base',
      );
    });

    test('works with the cache, and renders share nothing', () {
      ViewEngine engine = ViewEngine(
        const MemoryTemplateLoader(<String, String>{
          'base': "@stack('js')|@yield('title', 'none')",
          'a': "@extends('base')\n@section('title', 'A')\n@push('js')+@end",
          'b': "@extends('base')",
        }),
      );
      expect(engine.render('a'), '+|A');
      expect(engine.render('b'), '|none');
      expect(engine.render('a'), '+|A');
    });

    test('@extends must come first, and only once', () {
      expect(
        () => render("<p>x</p>\n@extends('base')"),
        throwsA(
          isA<ViewException>()
              .having(
                (ViewException e) => e.message,
                'message',
                '@extends must be the first thing in a template',
              )
              .having((ViewException e) => e.line, 'line', 2),
        ),
      );
      expect(
        () => render("@extends('base')\n@extends('other')"),
        throwsA(
          isA<ViewException>().having(
            (ViewException e) => e.message,
            'message',
            'a template can have only one @extends',
          ),
        ),
      );
    });

    test('a @section with no @end', () {
      expect(
        () => render("@extends('base')\n@section('content')\nx"),
        throwsA(
          isA<ViewException>()
              .having(
                (ViewException e) => e.message,
                'message',
                '@section has no @end',
              )
              .having((ViewException e) => e.template, 'template', 'main')
              .having((ViewException e) => e.line, 'line', 2),
        ),
      );
    });

    test('an unknown layout', () {
      expect(
        () => render("\n@extends('nope')"),
        throwsA(
          isA<ViewException>()
              .having(
                (ViewException e) => e.message,
                'message',
                'template "nope" not found',
              )
              .having((ViewException e) => e.template, 'template', 'main')
              .having((ViewException e) => e.line, 'line', 2),
        ),
      );
    });

    test('a layout that extends itself', () {
      expect(
        () => render("@extends('main')"),
        throwsA(
          isA<ViewException>().having(
            (ViewException e) => e.message,
            'message',
            contains('extend itself'),
          ),
        ),
      );
    });

    test('a section name must be a string', () {
      expect(() => render('@yield(name)'), throwsA(isA<ViewException>()));
    });
  });

  group('stacks', () {
    test('a @stack before the @push still gets it', () {
      expect(
        render(
          "<head>@stack('js')</head>\n"
          "@push('js')\n"
          '<script src="{{ file }}"></script>\n'
          '@end\n'
          '<body></body>',
          <String, Object?>{'file': 'a.js'},
        ),
        '<head><script src="a.js"></script>\n</head>\n<body></body>',
      );
    });

    test('the page, includes, components and the layout all push', () {
      expect(
        render(
          "@extends('base')\n"
          "@push('js')page @end\n"
          "@section('content')\n"
          "@include('part')\n"
          '@!card()\n'
          '@end\n',
          <String, Object?>{},
          <String, String>{
            'base':
                "[@stack('js')]@yield('content')"
                "@push('js')layout @end"
                "@prepend('js')first @end",
            'part': "@push('js')include @end",
            'components/card': "@push('js')component @end",
          },
        ),
        '[first page include component layout ]',
      );
    });

    test('an empty stack prints nothing, and can show twice', () {
      expect(
        render("[@stack('a')][@stack('b')][@stack('b')]@push('b')+@end"),
        '[][+][+]',
      );
    });

    test('a @stack inside a @push is filled, in both orders', () {
      Map<String, String> layout = <String, String>{'l': "@stack('a')"};
      expect(
        render(
          "@extends('l')\n"
          "@push('a') A[@stack('b')] @end\n"
          "@push('b') B @end\n",
          <String, Object?>{},
          layout,
        ),
        ' A[ B ] ',
      );
      expect(
        render(
          "@extends('l')\n"
          "@push('b') B @end\n"
          "@push('a') A[@stack('b')] @end\n",
          <String, Object?>{},
          layout,
        ),
        ' A[ B ] ',
      );
    });

    test('a stack that pushes to itself ends, and leaves no mark', () {
      String html = render("[@stack('a')]@push('a') +@stack('a') @end");
      expect(html, isNot(contains('\u0000')));
      expect(html, isNot(contains('stack')));
      expect(html, startsWith('[ +'));
    });

    test('a mark made by a user is not filled', () {
      String forged = '\u0000stack123:s\u0000';
      expect(
        render("{{ text }}|@stack('s')@push('s')+@end", <String, Object?>{
          'text': forged,
        }),
        '$forged|+',
      );
    });

    test('@once in a @push pushes once', () {
      expect(
        render(
          "@!item()@!item()[@stack('js')]",
          <String, Object?>{},
          <String, String>{
            'components/item': "@push('js')\n@once\njs\n@end\n@end\n",
          },
        ),
        '[js\n]',
      );
    });

    test('a @stack in a slot of a component is filled', () {
      expect(
        render(
          "@box()@stack('js')@end@push('js')+@end",
          <String, Object?>{},
          <String, String>{'components/box': '<b>{{ \$slot }}</b>'},
        ),
        '<b>+</b>',
      );
    });
  });

  group('@method and @csrf', () {
    test('@method prints the hidden field, escaped', () {
      expect(
        render("@method('PUT') @method(verb)", <String, Object?>{'verb': '">'}),
        '<input type="hidden" name="_method" value="PUT"> '
        '<input type="hidden" name="_method" value="&quot;&gt;">',
      );
    });

    test('@csrf prints the shared token, escaped', () {
      ViewEngine engine = ViewEngine(
        const MemoryTemplateLoader(<String, String>{'form': '<form>\n@csrf\n'}),
      );
      expect(
        engine.render(
          'form',
          <String, Object?>{'csrfToken': 'from the page data'},
          <String, Object?>{'csrfToken': () => 'a"b'},
        ),
        '<form>\n<input type="hidden" name="_token" value="a&quot;b">',
      );
    });

    test('a csrfToken that throws is a ViewException with the line', () {
      ViewEngine engine = ViewEngine(
        const MemoryTemplateLoader(<String, String>{'form': '<form>\n@csrf\n'}),
        globals: <String, Object?>{
          'csrfToken': () => throw StateError('no store'),
        },
      );
      expect(
        () => engine.render('form'),
        throwsA(
          isA<ViewException>()
              .having(
                (ViewException e) => e.message,
                'message',
                contains('no store'),
              )
              .having((ViewException e) => e.template, 'template', 'form')
              .having((ViewException e) => e.line, 'line', 2),
        ),
      );
    });

    test('@csrf with no token is an error', () {
      expect(
        () => render('<form>\n@csrf\n</form>'),
        throwsA(
          isA<ViewException>()
              .having(
                (ViewException e) => e.message,
                'message',
                contains('@csrf needs a session'),
              )
              .having((ViewException e) => e.line, 'line', 2),
        ),
      );
    });
  });

  group('custom directives', () {
    ViewEngine engine() => ViewEngine(
      const MemoryTemplateLoader(<String, String>{
        'main': '@shout(name, 2) @!bold() @hello()',
        'text': '@shout and @shout (see the docs)',
        'bad': '\n@fail(1)',
        'components/bold': 'component',
      }),
      directives: <String, ViewDirective>{'shout': Shout()},
    );

    test('print escaped text, or HTML with SafeString', () {
      ViewEngine views = engine()
        ..directive('bold', Bold())
        ..directive('hello', Hello());
      expect(
        views.render('main', <String, Object?>{'name': '<ann>'}),
        '&lt;ANN&gt;!! component Hello &lt;ann&gt;',
      );
      views = ViewEngine(
        const MemoryTemplateLoader(<String, String>{'main': '@bold(name)'}),
      )..directive('bold', Bold());
      expect(
        views.render('main', <String, Object?>{'name': '<ann>'}),
        '<b>&lt;ann&gt;</b>',
      );
    });

    test('with no ( ), or with args that do not parse, it stays text', () {
      expect(engine().render('text'), '@shout and @shout (see the docs)');
    });

    test('a directive added after a render works in cached templates', () {
      ViewEngine views = ViewEngine(
        const MemoryTemplateLoader(<String, String>{'main': '@hello()'}),
      );
      expect(views.render('main'), '@hello()');
      views.directive('hello', Hello());
      expect(
        views.render('main', <String, Object?>{'name': 'Ann'}),
        'Hello Ann',
      );
    });

    test('a built-in name or a bad name throws', () {
      for (String name in <String>['if', 'end', 'section', 'csrf', 'class']) {
        expect(
          () => engine().directive(name, Shout()),
          throwsA(
            isA<ViewException>().having(
              (ViewException e) => e.message,
              'message',
              contains('@$name is a built-in tag'),
            ),
          ),
        );
      }
      expect(
        () => engine().directive('my-tag', Shout()),
        throwsA(isA<ViewException>()),
      );
    });

    test('an error in a directive names the template and the line', () {
      ViewEngine views = engine()..directive('fail', Fail());
      expect(
        () => views.render('bad'),
        throwsA(
          isA<ViewException>()
              .having((ViewException e) => e.message, 'message', contains('no'))
              .having((ViewException e) => e.template, 'template', 'bad')
              .having((ViewException e) => e.line, 'line', 2),
        ),
      );
    });
  });

  group('old templates', () {
    test('the new tag names stay text with no ( )', () {
      String text =
          'The @section and @yield of @extends, a @stack to @push or '
          '@prepend, send @csrf with @method. @csrf';
      expect(render(text), text);
    });

    test('with a space before (, text that is not a tag stays text', () {
      String text =
          'A @section (see below) and a @push (to the stack) or '
          "@yield ('a', 'b', 'c') and @method (GET or POST).";
      expect(render(text), text);
    });

    test('prose with a space before ( and a word in it stays text', () {
      for (String text in <String>[
        'call me by @method (preferred) ok',
        'the @yield (curve) is',
        'the @stack (overflow) site',
        'class A @extends (Base) here',
        '@if(true)\ngit @push (force) now\n@end\n',
        'git\n@push (force)\nnow',
        '@extends (Base)\n',
        'a @section (intro, part) and @prepend (x)',
      ]) {
        String expected = text.startsWith('@if')
            ? 'git @push (force) now\n'
            : text;
        expect(render(text), expected, reason: text);
      }
    });

    test('with a space before ( and a quoted name, it is a tag', () {
      expect(
        render("a @yield ('t', 'x') b @method ('PUT')\n@stack ('js')\n"),
        'a x b <input type="hidden" name="_method" value="PUT">\n',
      );
    });

    test('a component with the name of a new tag still wins', () {
      expect(
        render(
          "@stack({ gap: 2 })x @end @!section({ id: 'a' })",
          <String, Object?>{},
          <String, String>{
            'components/stack': '<div gap="{{ gap }}">{{ \$slot }}</div>',
            'components/section': '<section id="{{ id }}">',
          },
        ),
        '<div gap="2">x </div> <section id="a">',
      );
    });

    test('a page with no new tag prints the same', () {
      expect(
        render(
          '@if(on)\n<a href="mailto:me@mail.com">@media</a>\n@end\n',
          <String, Object?>{'on': true},
        ),
        '<a href="mailto:me@mail.com">@media</a>\n',
      );
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
