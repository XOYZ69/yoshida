+++
title = "Diagnostics"
description = "How problems are reported, and every error code with its fix."
+++

Every problem yoshida finds is a **diagnostic** with a severity, a stable numeric code, a place and a message. Loading and checking report **all** problems, not just the first, and rendering starts only when there are zero errors.

| Severity | Meaning |
| --- | --- |
| `error` | The project cannot be rendered. Fix it |
| `warning` | Rendering works but something is probably wrong (a text was cut, a font is missing) |
| `hint` | Information only |

Codes are stable and never reused. The first digit groups them: 1xxx file and format, 2xxx card data, 3xxx expressions and layout, 4xxx assets, 5xxx limits.

## Reading a message

On the command line:

```txt
designs/tour.design.json:41:17: error[3002]: unknown name 'levl'
  at /layers/4/repeat/count (expression bytes 0..4)
  hint: did you mean 'level'?
```

`file:line:column`, severity and code, the message (with `card <id>:` in front when it belongs to one card), the JSON pointer of the field, the byte range inside an expression when there is one, and a hint. Hints such as *did you mean 'color'?* come from a closest-name search over the valid names.

## JSON shape

`yoshida check --format json`, `yoshida render --format json`, the server's 422 response and the WebAssembly module all use this object per diagnostic:

```json
{
  "severity": "error",
  "code": 3002,
  "file": "designs/tour.design.json",
  "path": "/layers/4/repeat/count",
  "line": 41,
  "col": 17,
  "span": [0, 4],
  "message": "unknown name 'levl'",
  "hint": "did you mean 'level'?",
  "card": null
}
```

| Field | Meaning |
| --- | --- |
| `severity` | `error`, `warning` or `hint` |
| `code` | Number from the table below |
| `file` | Project path of the file; empty for project-wide problems |
| `path` | JSON Pointer to the field (`/layers/3/box/x`; inside groups `/layers/2/layers/0/box/x`) |
| `line`, `col` | 1-based position in the file (0 when unknown) |
| `span` | `[start, end]` byte range inside the expression string, or `[0, 0]` |
| `message` | What is wrong |
| `hint` | What to try, or `null` |
| `card` | The card id for render-time problems, or `null` |

## In the editor

The [Problems panel](@/docs/builder-problems.md) collects them, groups identical problems from many cards into one block and jumps to the field, the card or the line when you click.

## Codes

### 1xxx: files and format

| Code | Severity | Meaning |
| --- | --- | --- |
| 1001 | error | JSON syntax error |
| 1101 | error | Unknown field |
| 1102 | error | Missing required field (also: a CSV file that no set uses is a *warning* with this code) |
| 1103 | error | Wrong JSON type for the field's kind, or a word that is not one of an enum's options |
| 1104 | error | `format` missing |
| 1105 | error | Unsupported `format` version |
| 1106 | error | Param, constant or function name is invalid, is a reserved word, or collides with another param, constant or function name |
| 1107 | error | Param has neither `default` nor `required` |
| 1108 | error | Duplicate or invalid layer id |
| 1109 | error | Polygon has fewer than 3 points (2 for an open polygon) |
| 1110 | error | Image `w` and `h` both `auto` |
| 1111 | error | `repeat` needs exactly one of `count` / `each`; a polygon needs exactly one of `points` / `shape` |
| 1112 | error | `extends` across different layer types (including a group), or of a divider |
| 1113 | warning | A design function has the name of a built-in function; the design's function is used in this design instead of the built-in |
| 1201 | error | File not found |
| 1202 | error | CSV syntax error (also a missing header row, or a row with the wrong number of fields) |
| 1203 | error | Path escapes the project root |

### 2xxx: card data

| Code | Severity | Meaning |
| --- | --- | --- |
| 2001 | warning | Card sets an unknown param |
| 2002 | error | Value outside `min` / `max` / `max_length` |
| 2003 | error | Required param missing |
| 2004 | error | Duplicate card id |
| 2005 | error | Card id not safe as a file name |
| 2006 | error | Card value has the wrong type, or is not an enum option |

### 3xxx: expressions and layout

| Code | Severity | Meaning |
| --- | --- | --- |
| 3001 | error | Expression syntax error |
| 3002 | error | Unknown name or function |
| 3003 | error | Type mismatch or wrong function arguments |
| 3004 | error | Reference or `extends` cycle (also: an iteration reading a later one, a group's `translate` reading a layer inside it) |
| 3005 | error | Reference to a repeated layer without an iteration index, or into nested repeats |
| 3006 | error | Unit not valid in this field |
| 3101 | error | Negative width or height (at render time) |
| 3102 | error | List index or iteration index out of range, or `last()` of an empty list (at render time) |
| 3103 | error | Math error (division by zero, empty list average/min/max, result not a finite number, value outside a function's domain) (at render time) |
| 3104 | error | List lookup by a key no item has (at render time) |
| 3105 | error | Text is not a valid date, time or date-time, or a date token is used on a time-only value (at render time) |
| 3106 | error | Text result over 10 000 bytes (at render time) |
| 3107 | error | Argument out of range: `roman` outside 1 to 3999, an empty `part` separator, `rand_int` with `lo` greater than `hi` (at render time) |
| 3201 | warning | Text truncated by `max_lines` |
| 3202 | hint | Layer entirely outside the canvas |
| 3203 | warning | Text does not fit `max_width` / `max_height` even at `min_size` |

### 4xxx: assets

| Code | Severity | Meaning |
| --- | --- | --- |
| 4001 | error | Image not found or unreachable (placeholder in preview) |
| 4002 | error | Image could not be decoded |
| 4003 | warning | Neither the font nor the bundled fallback fonts have glyphs for some characters (drawn as boxes) |
| 4004 | error | Font name not declared in `fonts` |
| 4005 | warning | Font file missing or not a TrueType/OpenType font; the default font is used |

### 5xxx: limits

| Code | Severity | Meaning |
| --- | --- | --- |
| 5001 | error | A limit was exceeded: canvas size, layers after repeat (the message names the layers that use most of it), repeat iterations, group nesting, cards per set, image size. See [Limits and Versioning](@/docs/limits-and-versioning.md) |

## Common fixes

| You see | Usually means | Try |
| --- | --- | --- |
| `1101 unknown field 'colour'` | A typo | Use the hint: `color` |
| `1107` | A param with no default | Add `"default"` or `"required": true` |
| `1108` | Two layers with the same id, maybe in different groups | Rename one (the editor updates references) |
| `3002 unknown name` | Typo in a param or `@layer` | Check [Names and references](@/docs/expressions-names-and-references.md) |
| `3003` in a text | A list or item inside `{...}` | Use a field or an index |
| `3005` | Referencing a layer that uses `repeat` | Pick an iteration, `@layer[0].bounds.cx`, or reference a group around it |
| `5001 ... visible layers after repeat` | A card draws more than 500 layers | Hide variants with `visible`, see [the layer limit](@/docs/repeat.md#the-layer-limit) |
| `3006` | `%` in `size`, `radius`, ... | Use `vw` or `vh` |
| `3104` | `stats.Speed` on a card without that key | Add the item, or check spelling and case; `get(stats, 'Speed', 0)` gives a fallback |
| `3103` from `avg`, `min` or `max` | An empty list | Guard with `len(list) > 0`, or give a fallback in the expression |
| `3105` | A date that is not `YYYY-MM-DD` | Use the ISO form; see [Dates and times](@/docs/expressions-functions-dates.md#accepted-text) |
| `1113` | A design function named like a built-in | Rename the function, or keep the name on purpose: the design's function is used in this design |
| `4001` | Image path wrong, URL unreachable | Fix the path; with `--preview` you get a placeholder |
| `4005` | Font file missing | Add the file, or fix the `fonts` path |
