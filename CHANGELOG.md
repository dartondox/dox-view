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
