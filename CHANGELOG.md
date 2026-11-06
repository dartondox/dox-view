## Unreleased

- New tags: `@isset`, `@empty`, `@auth`, `@guest`, `@env`, `@production`, `@once`, `@verbatim`, `@class`, `@checked`, `@selected` and `@disabled`. A component with the same name still wins. With no `( )`, `@isset`, `@empty`, `@env`, `@class`, `@checked`, `@selected` and `@disabled` stay plain text.
- `ViewEngine` takes `environment` for `@env` and `@production`. By default it is `APP_ENV`.
- Components get `$attributes`: the props as HTML attributes, with `merge()` for default attributes. The values are escaped.
- Components get `$slot`, the same as `$slots.main`. Before, `$slots.main` was missing when the component had no body. Now both are always there, as empty text. So `{{ $slots.main ?? 'x' }}` no longer prints `x` for an empty body.
- An empty `SafeString` is now false in `@if`, like empty text. An empty named slot is false too.
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
