## Unreleased

- Fix: text like `@empty (none)` or `@class (see docs)` threw an error since 3.1.0. The new rule is for a tag with a space before the `(`, in the middle of a line. It is a tag only when its args are a valid expression. `@isset`, `@empty` and `@env` also need an `@end` after them. Else the text stays as it is. A tag with no space, or alone on its line, works as before. Templates that worked on 3.1.0 still work.
- New: `$attributes.except(['variant'])` leaves out props that are only for the logic of a component. It can go before `merge()`.
- Fix: spaces after the last tag at the end of a file stayed in the output. A tag alone on its line now removes them, like it removes the line break.
- New: layouts with `@extends('layouts/app')`, `@section('name') ... @end` and `@yield('name')`. `@yield('title', 'Home')` has a default. `@section('title', 'Home')` is the short form. A layout can extend another layout. In a page with `@extends`, text outside a section is not printed.
- New: `@stack('scripts')` prints what `@push('scripts') ... @end` and `@prepend('scripts') ... @end` add. Pushes work from the page, its layout, includes and components. A `@stack` that comes before the `@push` still prints it. A `@stack` inside a `@push` works too.
- New: `@csrf` prints the hidden `_token` field. It must be alone on its line. With no session it throws a `ViewException`. `@method('PUT')` prints the hidden `_method` field.
- New: your own tags. `View.directive('datetime', DateTimeDirective())` adds `@datetime(...)`. The class implements `ViewDirective`. The output is escaped, but a `SafeString` is not. `ViewConfig` and `ViewEngine` take `directives` too. The name of a built-in tag throws a `ViewException`. `Scope` is now exported.
- Note: `@extends(...)`, `@section(...)`, `@yield(...)`, `@stack(...)`, `@push(...)`, `@prepend(...)` and `@method(...)` were plain text before. Now they are tags. With no `( )` they stay text. With a space before the `(`, they are tags only when the first argument is text in quotes, so text like `git @push (force)` stays text. `@csrf` is a tag only alone on its line. A component with the same name still wins. To print one as text, write `@@push(...)`.
- Docs: a `$auth` key in the data of `View.render` makes `@auth` true there. Do not pass data from the user as `$auth`.

## 3.1.0

- New tags: `@isset`, `@empty`, `@auth`, `@guest`, `@env`, `@production`, `@once`, `@verbatim`, `@class`, `@checked`, `@selected` and `@disabled`. A component with the same name still wins. With no `( )`, `@isset`, `@empty`, `@env`, `@class`, `@checked`, `@selected` and `@disabled` stay plain text. `@auth`, `@guest`, `@production`, `@once` and `@verbatim` are tags only alone on their line, so text like `@once upon a time` stays text. `@env` and `@production` ignore case, like the cache default.
- `ViewEngine` takes `environment` for `@env` and `@production`. By default it is `APP_ENV`.
- Components get `$attributes`: the props as HTML attributes, with `merge()` for default attributes. The values are escaped.
- Components get `$slot`, the same as `$slots.main`. Before, `$slots.main` was missing when the component had no body. Now both are always there, as empty text. So `{{ $slots.main ?? 'x' }}` no longer prints `x` for an empty body.
- An empty `SafeString` (no text at all) is now false in `@if`, like empty text. So a named slot with no text is false. A named slot with only spaces is still true.
- Fix: an app global named `errors` was hidden by the empty `errors` that every view gets. Now the global shows when there are no validation errors.
- Fix: `{{ errors.email }}` threw an error when there was no session, and in `View.render`. Now `errors` is always there: an empty map when there is no session, so the template prints nothing.
- Fix: the `toJson()` of an object was kept for the life of the object. A change to the object (for example a global) did not show in later renders. Now the cache lasts only one render.

## 3.0.0

- The first stable release.

## 3.0.0-rc.1

- Fix: `View.configure()` dropped the globals added before it with `View.global()`. Now it keeps them. The globals of the config win on the same name.

## 3.0.0-alpha.3

- `ViewProvider` (was a DoxService): extend it in your app, `shutdown()` is optional.

## 3.0.0-alpha.2

- Components and layouts now see the request helpers of `view()`: `request`, `csrfField()`, `csrfToken()`, `errors`, `old()` and `session()`. Before, a form inside a layout failed with `can not read "path" of null`.
- `ViewEngine.render` takes a third map, `shared`: data that components see too.
- README: credits to Edge.js.

## 3.0.0-alpha.1

- First version.
- Templates in `.dox.html` files, rendered with `view(req, name, data)` or `View.render(name, data)`.
- `{{ }}` escapes HTML, `{{{ }}}` does not. `{{-- --}}` comments.
- `@if`, `@elseif`, `@else`, `@unless`, `@each` (with index, key, `$loop` and `@else`), `@let`, `@assign`, `@include` and `@includeIf`.
- Components with props and slots, for layouts too. A template in `components/` is also a tag, like `@button(...)`.
- Expressions with fields, math, logic, `??`, `?:`, functions and methods. Objects with `toJson()` work, like Dox models.
- With a session: `csrfField()`, `csrfToken()`, `errors`, `old()` and `session()`. `route()` and `request` in every view.
- Parsed templates are cached, but not when `APP_ENV` is `development` or `local`.
- Errors name the template and the line.
