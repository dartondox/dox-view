## Unreleased

- Requires Dart 3.14 or newer.
- New: with `bladeOutput`, a number in `$attributes` prints like `{{ }}`. `1.0` is `title="1"` and `0.5` stays `0.5`. With the option off, nothing changes: `1.0` is `title="1.0"`.
- Fix: `@empty (none)` alone on its line threw `@empty has no @end`. Now a tag with a body and a space before the `(`, like `@isset (x)` or `@empty (x)`, is a tag only when its own `@end` comes after it, on any line. The `@end` of a block around it does not count. Else the text stays as it is. Templates that worked before still work the same.
- Fix: many nested tags with a space before the `(`, like `@isset (x)`, made the parse very slow. Each extra level took about twice as long, so 40 levels would take days. Now the parser counts the `@end` tags once, so the time grows in a straight line.
- Fix: text like `@empty (none)` or `@class (see docs)` threw an error since 3.1.0. The new rule is for a tag with a space before the `(`, in the middle of a line. It is a tag only when its args are a valid expression. `@isset`, `@empty` and `@env` also need an `@end` after them. Else the text stays as it is. A tag with no space works as before. Templates that worked on 3.1.0 still work.
- New: `$attributes.except(['variant'])` leaves out props that are only for the logic of a component. It can go before `merge()`.
- Fix: spaces after the last tag at the end of a file stayed in the output. A tag alone on its line now removes them, like it removes the line break.
- New: layouts with `@extends('layouts/app')`, `@section('name') ... @end` and `@yield('name')`. `@yield('title', 'Home')` has a default. `@section('title', 'Home')` is the short form. A layout can extend another layout. In a page with `@extends`, text outside a section is not printed.
- New: `@stack('scripts')` prints what `@push('scripts') ... @end` and `@prepend('scripts') ... @end` add. Pushes work from the page, its layout, includes and components. A `@stack` that comes before the `@push` still prints it. A `@stack` inside a `@push` works too.
- New: `@csrf` prints the hidden `_token` field. It must be alone on its line. With no session it throws a `ViewException`. `@method('PUT')` prints the hidden `_method` field.
- New: your own tags. `View.directive('datetime', DateTimeDirective())` adds `@datetime(...)`. The class implements `ViewDirective`. The output is escaped, but a `SafeString` is not. `ViewConfig` and `ViewEngine` take `directives` too. The name of a built-in tag throws a `ViewException`. `Scope` is now exported.
- Note: `@extends(...)`, `@section(...)`, `@yield(...)`, `@stack(...)`, `@push(...)`, `@prepend(...)` and `@method(...)` were plain text before. Now they are tags. With no `( )` they stay text. With a space before the `(`, they are tags only when the first argument is text in quotes, so text like `git @push (force)` stays text. `@csrf` is a tag only alone on its line. A component with the same name still wins. To print one as text, write `@@push(...)`.
- Docs: a `$auth` key in the data of `View.render` makes `@auth` true there. Do not pass data from the user as `$auth`.
- New: `@include('card', { title: 'Hi' })` gives more variables to the template. The map wins over the variables of the page, and the page does not see it after the include. `@includeIf` takes the map as a third argument. A value that is not a map throws a `ViewException`.
- New: `@includeWhen(condition, 'name')` includes a template when the condition is true. It does the same as `@includeIf`, which did not change.
- New: `$loop` also has `iteration`, `count`, `remaining`, `even`, `odd`, `depth` and `parent`. The first round is odd. `index`, `first`, `last` and `length` are the same as before.
- New: `@json(value)` prints a value as JSON. `<`, `>`, `&`, `'` and the line separators U+2028 and U+2029 are written as `\uXXXX`, so it is safe inside a `<script>` block and inside an attribute in single quotes. The `json(value)` function gives the same text for `{{ }}`. In Dart it is `SafeString.json(value)`. A value that can not be JSON throws a `ViewException`.
- New: `@error('email') ... @end` shows its body when `errors` has a message for the field. `message` is the first message. A name with dots reads the key `'user.email'` first, then `email` inside `user`. With no errors it prints nothing.
- New: a warning for Blade names that are not Dox tags: `{!! !!}`, `@foreach`, `@forelse`, `@for`, `@while`, `@switch`, `@php`, `@show`, `@parent`, `@stop`, and `@endif` with the other `@end...` names. They are still printed as text. The warning goes to `stderr`, one time each, with the template, the line and the Dox way. `ViewConfig(bladeWarnings: false)` turns it off. `ViewEngine` takes `warningSink` to send the warnings somewhere else.
- New: three options in `ViewConfig` and `ViewEngine`. All three are off by default, so the output of an app does not change. Turn each one on in `ViewConfig`. `strictVariables`: a variable that does not exist throws a `ViewException` with its name. `@isset(x)`, `@empty(x)`, `x ?? 'default'` and `x?.name` do not throw. `stringZeroIsFalse`: the text `'0'` is false in a condition. `bladeOutput`: `true` prints `1`, `false` prints nothing, and `10.0` prints `10`.
- Note: `@includeWhen(...)`, `@json(...)` and `@error(...)` were plain text before. Now they are tags. With no `( )` they stay text. `@json` and `@includeWhen` are tags only with the `(` right after the name, so text like `the @json (format)` stays text. With a space before the `(`, `@error` is a tag only when the first argument is text in quotes, so text like `an @error (see log)` stays text. A component with the same name still wins. A directive of the app can not use these three names.
- Note: with the `(` right after the name, these three are always tags. So old text like `@json(foo bar)`, `@error(see log)` or `@includeWhen(x)` printed as text before, and can now stop the render with a `ViewException`. To print it as text, write `@@json(...)`.
- Note: every template now has a `json` function. A variable named `json` in your data or your globals still wins. `{{ $loop }}` as a whole now prints the new fields too.

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
