+++
title = "Expressions: Templates"
description = "Text and path fields with {expression} holes."
+++

`text` and `path` fields are **templates**: literal text with `{expression}` holes.

```json
"text": "Level {level} {upper(card_type)}"
"src": "assets/images/attributes/attribute-{attribute}.png"
```

{% raw %}- `{{` and `}}` produce literal braces: `"{{not a hole}}"`.{% endraw %}
- A hole holds any [expression](@/docs/expressions.md), including names, operators and function calls: `{fmt(price, 2)}`, `{foil ? 'FOIL' : ''}`, `{stats.Speed}`.
- A newline character forces a line break in `text` fields, whether it is written in the template or comes from a param value.

### Line breaks in values

In JSON, `\n` inside a string *is* a newline character. So a `text` param whose default or card value is `"one\ntwo"` breaks the line, just like a template `"text": "one\ntwo"`. A double-escaped `"one\\ntwo"` is a backslash followed by `n`, and is drawn literally as `one\ntwo`. In a CSV cell, type a real line break inside a quoted cell.

## How values are converted

| Value | Becomes |
| --- | --- |
| number | The shortest decimal that round-trips: `5`, `0.5`, never `5.0` |
| bool | `true` or `false` |
| text | unchanged |
| color | `#RRGGBBAA` (8-bit) |
| list or list item | error 3003; use a field or an index |

Use `fmt(number, decimals)` when you need a fixed number of digits.

## `path` fields

A `path` field is a template whose result must be a project path or an `https://` URL: image `src`. Because the path is built at render time, the check "does the file exist" also happens at render time, per card (error 4001).

When you rename or move a file in the editor, templates that build paths from params cannot be rewritten automatically; the Files tab lists them first so you can fix them by hand. See [Builder: Files](@/docs/builder-files.md).

## No concatenation operator

There is no `+` for text. Combine pieces with a template: `"{first} {last}"`.
