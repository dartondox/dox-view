---
name: dox-view-guide
description: Use when you add or edit server-rendered HTML pages in a Dox (Dart) app with the dox_view package. Covers .dox.html templates, view() from a route, output and escaping, @if/@each tags, layouts, components, forms with CSRF, globals and custom tags.
---

# dox_view guide

`dox_view` is the template engine of Dox. Templates are `.dox.html` files in `resources/views`. Dox fills them with data and sends HTML as the response. For routes and controllers, see the `dox-core-guide` skill.

## Install and set up

Fast way: `dox add view`. It adds the package, `lib/providers/view_provider.dart`, `resources/views/` and a sample `welcome.dox.html`. It never overwrites a file. The steps below are the same by hand, with a config file for globals.

1. Add the package:

```bash
dart pub add dox_view
```

2. Make a config file, `lib/config/view.dart`:

```dart
import 'package:dox_view/dox_view.dart';

ViewConfig viewConfig = ViewConfig(
  globals: <String, Object?>{'appName': 'My app'},
);
```

3. Make a provider in `lib/providers/view_provider.dart`. Dox finds every `DoxProvider` class. Run `dart run build_runner build` so it is in `lib/generated/container.g.dart`. Each isolate then sets up the engine.

```dart
import 'package:dox_view/dox_view.dart';
import '../config/view.dart';

class AppViewProvider extends ViewProvider {
  AppViewProvider() : super(viewConfig);
}
```

## Render a view

`view(req, name, data)` renders a template and sends it as HTML. Leave out the `.dox.html` extension.

```dart
import 'package:dox_core/dox_core.dart';
import 'package:dox_view/dox_view.dart';

@Inject()
class UserController {
  DoxResponse show(DoxRequest req) {
    return view(req, 'users/show', <String, dynamic>{
      'user': user,
      'posts': posts,
    });
  }
}
```

This reads `resources/views/users/show.dox.html`:

```html
<h1>{{ user.name }}</h1>
```

`View.render('emails/welcome', {'name': 'Ann'})` gives the HTML as a `String`. There is no request in it, so `@guest` shows and `errors` is empty.

## Output and escaping

- `{{ value }}` prints and escapes HTML.
- `{{{ value }}}` prints with no escape. Use it only for HTML you trust.
- `{{-- comment --}}` is not in the output.
- `@{{ name }}` prints `{{ name }}` as text. `@@if` prints `@if`.
- `null` and a missing variable print nothing. `true` prints `true`.
- A `SafeString('<b>x</b>')` is printed with no escape.

## Expressions

Inside `{{ }}` and tags you can use: values (`'text'`, `42`, `true`, `null`), lists `[1, 2]`, maps `{ name: 'Ann' }`, fields (`user.name`, `user?.name`, `items[0]`), math, compare (`==`, `!=`, `<`, `>`), logic (`&&`, `||`, `!`, `a ?? b`, `a ? b : c`) and function calls (`name.toUpperCase()`, `route('users.show', { id: 5 })`).

`+` joins text. Fields work on maps and on objects with `toJson()`. Lists, maps and text have `length`, `isEmpty`, `isNotEmpty`.

False values in conditions: `null`, `false`, `0`, `''`, an empty list, an empty map.

## Tags

Close every block tag with `@end`.

```html
@if(user.isAdmin)
  <a href="/admin">Admin</a>
@elseif(user.isEditor)
  <a href="/posts">Posts</a>
@else
  <p>Welcome</p>
@end

<ul>
  @each((user, index) in users)
    <li>{{ index + 1 }}. {{ user.name }}{{ $loop.last ? '' : ',' }}</li>
  @else
    <li>No users yet</li>
  @end
</ul>

@let(total = 0)
@each(item in cart)
  @assign(total = total + item.price)
@end
```

- Loop over a map: `@each((value, key) in settings)`.
- `$loop` has `index` (from 0), `iteration` (from 1), `first`, `last`, `count`, `remaining`, `even`, `odd`, `depth` and `parent`.
- `@isset(x) ... @end` shows when `x` is not null. `@empty(x) ... @end` shows when `x` is false.
- `@auth ... @end` and `@guest ... @end` use `req.auth`. `@env('local') ... @end` and `@production ... @end` use `APP_ENV`.
- `@include('partials/nav')` sees the page variables. `@include('partials/card', { title: 'Hi' })` adds more. `@includeIf(cond, 'name')` and `@includeWhen(cond, 'name', {map})` include on a condition.
- `@once ... @end` runs one time per render. `@verbatim ... @end` prints text as it is (use it for Vue or Alpine `{{ }}`).
- `@json(value)` prints safe JSON for a `<script>` or a single-quoted attribute. It throws `ViewException` for a value like `DateTime` that is not JSON.
- Attribute tags: `@class(['link', { active: isActive }])`, `@checked(x)`, `@selected(x)`, `@disabled(x)`.
- Put `@auth`, `@guest`, `@production`, `@once` and `@verbatim` alone on their line.

## Layouts: two ways

### A. Sections with @extends

`resources/views/layouts/app.dox.html`:

```html
<!DOCTYPE html>
<html>
  <head>
    <title>@yield('title', 'My app')</title>
    @stack('styles')
  </head>
  <body>
    <main>@yield('content')</main>
    @stack('scripts')
  </body>
</html>
```

`resources/views/home.dox.html`:

```html
@extends('layouts/app')

@section('title', 'Home')

@section('content')
  <p>Hello {{ user.name }}</p>
@end

@push('scripts')
  <script src="/js/home.js"></script>
@end
```

- `@extends` must be the first thing. Only one per template.
- Text outside a `@section` is not printed in a page with `@extends`.

### B. Components with props and slots

`resources/views/layouts/main.dox.html`:

```html
<html>
  <head><title>{{ title ?? 'My app' }}</title></head>
  <body>
    <header>{{ $slots.header }}</header>
    <main>{{ $slots.main }}</main>
  </body>
</html>
```

`resources/views/home.dox.html`:

```html
@component('layouts/main', { title: 'Home' })
  @slot('header')
    <h1>Welcome</h1>
  @end
  <p>Hello {{ user.name }}</p>
@end
```

- The second argument is the props. They are variables in the component, and `$props.x`.
- A component sees only its props, `$props`, `$slots`, `$slot`, `$attributes`, globals and the request helpers. It does NOT see the page variables. Pass what it needs as props.
- `@!component('x', {...})` has no body and no `@end`.
- A file in `resources/views/components/` is also a tag by its name. `components/button.dox.html` is `@button({ type: 'danger' }) Delete @end`. `components/form/input.dox.html` is `@!form.input({ name: 'email' })`.
- `$attributes` prints props as HTML attributes (escaped). Use `{{ $attributes.merge({ class: 'btn' }) }}` for defaults and `$attributes.except(['variant'])` to drop props.
- Never pass a map from user input as component props.

## Forms and CSRF

With `SessionMiddleware`, every template from `view()` gets `csrfField()`, `csrfToken()`, `errors`, `old('field')` and `session('key')`. Every template also gets `request.path`, `request.method` and `request.query`.

```html
<form method="POST" action="/posts/{{ post.id }}">
  @csrf
  @method('PUT')
  <input name="title" value="{{ old('title') }}">
  @error('title')
    <p class="error">{{ message }}</p>
  @end
  <button>Save</button>
</form>
```

- `@csrf` prints the hidden `_token` field for `CsrfMiddleware`. With no session it throws `ViewException`.
- `@method('PUT')` prints the hidden `_method` field. A browser form can only send GET and POST, so PUT, PATCH and DELETE routes need it. The `MethodOverride` middleware reads it.
- `@error('field') ... @end` shows `message` only when `errors` has that field.

## Globals and your own tags

```dart
// in ViewConfig(globals: ...) or anywhere, before or after configure
View.global('year', DateTime.now().year);
View.global('money', (num cents) => (cents / 100).toStringAsFixed(2));
```

```html
<footer>{{ appName }} {{ year }}</footer>
<a href="{{ route('users.show', { id: user.id }) }}">Profile</a>
```

`route()` is a global by default. A custom tag implements `ViewDirective`:

```dart
class DateTimeDirective implements ViewDirective {
  @override
  Object? render(List<Object?> args, Scope scope) {
    Object? value = args[0];
    DateTime time = value is DateTime ? value : DateTime.parse('$value');
    return '${time.day}/${time.month}/${time.year}';
  }
}

View.directive('datetime', DateTimeDirective()); // @datetime(post.createdAt)
```

The result is escaped. Return a `SafeString` for raw HTML. You can also pass `ViewConfig(directives: {...})`. A name like `if` or `json` throws `ViewException`.

## ViewConfig options

| Option | Default | Meaning |
| --- | --- | --- |
| `path` | `resources/views` | template folder |
| `cache` | on, off when `APP_ENV` is `development` or `local` | keep parsed templates |
| `globals` | `{}` | variables for all templates |
| `directives` | `{}` | custom tags |
| `strictVariables` | `false` | a missing variable throws `ViewException` |
| `stringZeroIsFalse` | `false` | text `'0'` is false in conditions |
| `bladeOutput` | `false` | print `true` as `1`, `false` as nothing, `10.0` as `10` |
| `bladeWarnings` | `true` | warn on stderr about `@foreach`, `@endif`, `{!! !!}` |

## Gotchas

- Use `@each(item in items)`, not `@foreach`. Use `@end`, not `@endif`. Use `{{{ }}}`, not `{!! !!}`. These other names print as plain text.
- A tag right after a letter or digit stays text (`me@mail.com`). Put a space before it.
- With `strictVariables`, `{{ user.name ?? 'Guest' }}` still throws when `user` is missing. Write `{{ user?.name ?? 'Guest' }}`.
- Add `*.dox.html` to `.prettierignore`. Prettier does not know `@` tags.
- Do not use `{{{ }}}` for user input. It is an XSS risk.
