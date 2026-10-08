# yoshida file format, version 1

Status: draft, 2026-10-07. This is the source of truth for designs, card data and expressions in yoshida (the Zig rewrite). The core, CLI, editor and server all follow it. Concept and reasoning: "yoshida: formats, expressions and errors" (Claude Doc). Behaviour of the old Python version for comparison: `reference/yoshida-python/README.md`.

Conventions: "must" means the core reports an error (`err`) when violated; "should" means a warning. Codes in brackets refer to section 9.

## 1. Files and project layout

A project is a folder. Every path inside a file is relative to the project root, uses `/`, and must not escape the root (`..` above the root is an error [1203]).

```text
my-cards/
  yoshida.json                 project manifest (optional)
  designs/<name>.design.json   designs
  cards/<name>.cards.json      card data (JSON)
  cards/<name>.cards.csv       card data (CSV)
  assets/...                   images and fonts, any structure
  .yoshida/                    caches, never committed
```

All files are UTF-8 without BOM. JSON files follow RFC 8259: no comments, no trailing commas. Use the `note` field (any object) for comments.

Every JSON file has `"format": 1` [1104 if missing, 1105 if unsupported]. A `"$schema"` key is allowed anywhere a file starts and is ignored by the core.

### Canonical formatting (`yoshida fmt`)

- 2 spaces indent, LF line endings, trailing newline.
- One property per line, except that an object containing only scalars, or an array containing only scalars or only arrays of scalars (such as `[x, y]` points), stays on one line when the whole line fits in 100 columns. The line length counts the indent, the `"key": ` prefix and the value, in UTF-16 code units. So `box`, `at`, `stroke` and most params sit on one line, while layers spread out.
- Key order is kept exactly as written; the formatter never reorders keys. The builder writes `id` and `type` first in new layers and keeps the order of existing ones.
- The CLI (`yoshida fmt`), the editor and the server save through the same rules, so files never churn between tools.

JSON Schemas for editor autocompletion live in `schema/` of the implementation: `design.schema.json`, `cards.schema.json` and `yoshida.schema.json` (draft 2020-12). Point `"$schema"` at them; the core ignores the key.

### Manifest `yoshida.json` (optional)

```json
{
  "format": 1,
  "name": "My Cards",
  "sets": [
    { "name": "core", "design": "designs/monster.design.json", "cards": "cards/core.cards.csv" }
  ]
}
```

`sets` pairs card files with designs. It is required for CSV card data (CSV cannot name its design) and optional for JSON card data, which names its own design.

## 2. Value kinds

Every field in this spec has one of these kinds. The kind decides how a JSON string in that field is read.

| Kind | JSON number | JSON bool | JSON string means |
| --- | --- | --- | --- |
| `number` | literal | error | expression yielding a number |
| `bool` | error | literal | expression yielding a bool |
| `color` | error | error | expression yielding a color (a hex literal is a valid expression) |
| `text` | error | error | template (section 6.6) |
| `path` | error | error | template, result must be a project path or `https://` URL |
| `enum(...)` | error | error | one of the listed words, literal only |
| `ident` | error | error | an identifier `[a-z_][a-z0-9_]*`, literal only |

A wrong JSON type is [1103]. Expressions are parsed and type-checked at load time, before any drawing.

## 3. Design file (`*.design.json`)

```json
{
  "format": 1,
  "name": "Example",
  "canvas": { "width": 1200, "height": 1800, "background": "#00000000" },
  "fonts": { "body": "assets/fonts/Body.ttf" },
  "params": { "title": { "type": "text", "default": "Untitled" } },
  "layers": [ ]
}
```

| Field | Kind | Required | Default | Meaning |
| --- | --- | --- | --- | --- |
| `name` | text literal | yes | | Display name |
| `canvas.width`, `canvas.height` | number | yes | | Pixels, may use params (not `%`, not layer references) |
| `canvas.background` | color | no | `#00000000` | Transparent by default |
| `fonts` | object of name → path | no | `{}` | Font families available to text layers. Names follow `ident`. `default` is built in (a bundled permissive font) and may be overridden |
| `params` | object of name → param | no | `{}` | Section 4 |
| `layers` | array of layers | yes | | Drawn in array order, first is bottom |

Unknown top-level fields are [1101].

## 4. Params

Params are the inputs a card can set. Names follow `ident` and must not equal a reserved name (`canvas`, `render`, `card`, `true`, `false`, `and`, `or`, `not`) or a function name [1106].

```json
"params": {
  "scale":       { "type": "number",  "default": 2, "min": 0.5 },
  "level":       { "type": "integer", "default": 4, "min": 0, "max": 12 },
  "title":       { "type": "text",    "default": "Untitled", "max_length": 60 },
  "foil":        { "type": "bool",    "default": false },
  "accent":      { "type": "color",   "default": "#660940" },
  "card_type":   { "type": "enum",    "options": ["spell", "trap"], "default": "spell" },
  "art":         { "type": "image",   "required": true },
  "ingredients": { "type": "list", "item": { "amount": "text", "unit": "text", "name": "text" }, "default": [] }
}
```

| Param field | Applies to | Meaning |
| --- | --- | --- |
| `type` | all | `number`, `integer`, `text`, `bool`, `color`, `enum`, `image`, `list` |
| `default` | all | Literal value used when the card does not set it. JSON literal, not an expression |
| `required` | all | `true`: the card must set it [2003]. A required param has no default |
| `label`, `note` | all | Shown in the editor |
| `group` | all | Free text naming the editor section the param belongs to, such as `"Monster stats"`. Params with the same `group` are shown together in the editor's params list and card form, in order of first appearance; params without one come first. No effect on rendering |
| `min`, `max` | number, integer | Inclusive range [2002] |
| `max_length` | text | Characters [2002] |
| `options` | enum | Non-empty array of strings |
| `item` | list | Object of field name → scalar type (`number`, `integer`, `text`, `bool`, `color`). Fields not given in an item take the type's zero value (`0`, `""`, `false`, `#00000000`) |

A param with neither `default` nor `required: true` is [1107]. An `image` param's value is a path or `https://` URL; it can be used in `path` fields via templates (`"src": "{art}"`) and in image functions (`avg_color(art)`).

The editor builds its card form and card table from `params`: a color picker for `color`, a dropdown for `enum`, a file picker for `image`, a sub-table for `list`. The order of `params` in the file is the order of the card form, within each `group`.

## 5. Layers

### 5.1 Fields every layer has

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `id` | ident | required | Unique within the design [1108] |
| `type` | enum | required | `rect`, `ellipse`, `polygon`, `text`, `image`, `group` (section 5.10), `divider` (section 5.11) |
| `note` | text literal | | Comment |
| `visible` | bool | `true` | `false`: the layer is not drawn; its values can still be referenced |
| `opacity` | number | `1` | 0 to 1, multiplies the layer's alpha |
| `rotate` | number | `0` | Degrees clockwise. Box layers (`rect`, `ellipse`, `image`) turn around their anchor point (`box.x`, `box.y`), text around `at`, polygons around the centre of their bounds. Values are taken modulo 360 |
| `anchor` | enum | `top-left` | Which point of the layer `at` / `box.x,box.y` refers to: `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right`; text layers also allow `baseline-left`, `baseline`, `baseline-right` |
| `repeat` | object | | Section 5.7 |
| `extends` | ident | | Section 5.8 |
| `effects` | array | `[]` | Section 5.9 |

Unknown fields are [1101], with a hint when a known field is one edit away.

Rotation is applied when the layer is composited, after effects. `@layer.bounds.*` always describes the unrotated layer, so references and alignment stay simple; `@layer.rotate` gives the angle.

### 5.2 `rect`

| Field | Kind | Default |
| --- | --- | --- |
| `box` | `{ x, y, w, h }` all number | required |
| `fill` | color | `#FFFFFFFF` |
| `radius` | number | `0` |
| `stroke` | `{ color: color, width: number }` | none |

The stroke is drawn centred on the edge. Width and height must be at least 0 [3101].

### 5.3 `ellipse`

Same fields as `rect` except `radius`. The ellipse fills `box`.

### 5.4 `polygon`

| Field | Kind | Default |
| --- | --- | --- |
| `points` | array of `[number, number]` | required, at least 3 points [1109] |
| `closed` | bool literal | `true` |
| `fill` | color | `#FFFFFFFF` (ignored when not closed) |
| `stroke` | `{ color, width }` | none |

Points are absolute canvas coordinates; `anchor` does not apply. Every coordinate is an expression, so polygons scale with params.

### 5.5 `text`

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `text` | text | required | Content. `\n` forces a line break |
| `at` | `{ x, y }` number | required | Anchor point |
| `font` | ident | `default` | Key of the design's `fonts` [4004 if missing] |
| `size` | number | `16` | Font size in pixels (em height) |
| `color` | color | `#000000FF` | |
| `align` | enum | `left` | `left`, `center`, `right`, `justify` (all lines but the last stretched to the wrap width; needs `wrap`) |
| `wrap` | number | none | Wrap width in pixels; greedy word wrap on spaces |
| `line_spacing` | number | `4` | Extra pixels between lines |
| `max_lines` | number | none | Lines beyond it are dropped and the last line ends in `…`; a warning [3201] is reported |
| `max_width` | number (x axis) | none | Auto-shrink: the text block may be at most this wide |
| `max_height` | number (y axis) | none | Auto-shrink: the text block may be at most this tall |
| `min_size` | number | `8` (or `size` if smaller) | Auto-shrink never goes below this size |

With `max_width` or `max_height`, the size shrinks from `size` in steps of 0.5 px (binary search) until the block fits, but not below `min_size`. Wrapping is redone at every size. If the text still does not fit at `min_size`, it is drawn at `min_size` and a warning [3203] is reported. `@layer.size` gives the size actually used.

The anchor refers to the bounding box of the whole text block (all lines). `baseline-*` anchors use the first line's baseline. With `wrap`, the block is `wrap` pixels wide (alignment happens inside it); without, it is as wide as the longest line. A line is as tall as the font's ascent minus its descent, and `line_spacing` is added between lines.

### 5.6 `image`

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `src` | path | required | PNG, JPEG, WebP (lossy and lossless), GIF (first frame) or BMP; project path or `https://` URL |
| `box` | `{ x, y, w, h }` number | required | `w` or `h` (not both) may be the string `"auto"` to keep the aspect ratio [1110 if both] |
| `fit` | enum | `fill` | `fill` stretches, `contain` letterboxes inside `box`, `cover` crops to fill `box` |
| `smoothing` | enum | `bilinear` | `nearest`, `bilinear` |

A missing or undecodable image is [4001]/[4002]: an error for final renders; the editor preview draws a checkered placeholder and continues.

`https://` (and `http://`) images are fetched by the front end, not the core: the CLI downloads each URL once per run (`--offline` turns this off), the editor fetches them in the browser, and the server does not download anything (an unreachable URL there is [4001]; upload the image with the project instead).

### 5.7 `repeat`

Draws the layer once per iteration. Inside the layer's fields the loop names are in scope.

```json
"repeat": { "count": "level", "index": "i" }
"repeat": { "each": "ingredients", "item": "ing", "index": "i" }
```

| Field | Kind | Meaning |
| --- | --- | --- |
| `count` | number or list | Number of iterations, rounded down, negative is 0. A list counts its items (`"count": "stats"` is `len(stats)`) |
| `each` | expression yielding a list | Iterate the list |
| `index` | ident | Name for the 0-based index (default `i`) |
| `item` | ident | Name for the current list item (only with `each`) |

Exactly one of `count` and `each` [1111]. Iterations above 1000 are [5001]. A repeated layer cannot be referenced from other layers [3005].

### 5.8 `extends`

`"extends": "other_id"` starts from the other layer's fields and applies this layer's fields on top. Objects (`box`, `at`, `stroke`, `repeat`) merge key by key; everything else is replaced. `id`, `extends` and `note` are never inherited. Both layers must have the same `type` [1112]; chains are allowed, cycles are [3004].

### 5.9 `effects`

Applied in order to the layer's own pixels before it is composited onto the canvas. Works on every layer type.

| Effect | Fields | Meaning |
| --- | --- | --- |
| `crop` | `side` (`top`, `bottom`, `left`, `right`), `length` number | Removes `length` px from that side of the layer's pixels; what remains is drawn at the same anchor point |
| `fade` | `side`, `length` number | Alpha ramps from opaque to transparent over the last `length` px toward `side` |
| `sharpen`, `detail`, `edge_enhance`, `find_edges` | `strength` number, default `1` | Convolution filters |

### 5.10 `group`

A group holds other layers and draws them as one picture, so they can be organised, moved, hidden, faded and rotated together.

```json
{ "id": "badge", "type": "group", "opacity": 0.9, "rotate": -8, "layers": [
  { "id": "badge_bg", "type": "ellipse", "box": { "x": 820, "y": 60, "w": 120, "h": 120 }, "fill": "accent" },
  { "id": "badge_text", "type": "text", "at": { "x": "@badge_bg.bounds.cx", "y": "@badge_bg.bounds.cy" }, "anchor": "center", "text": "{level}" }
] }
```

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `layers` | array of layers | required [1102] | Drawn in array order inside the group, first is bottom; groups may contain groups |
| `id`, `note`, `visible`, `opacity`, `rotate`, `effects` | | | As in 5.1, applied to the group's picture |

- A group has no position or size of its own. `@group.bounds.*` is the union of the bounds of its visible layers (all repeat iterations included); an empty or fully hidden group has zero bounds at the origin. `@group.opacity`, `.visible` and `.rotate` can be referenced as well.
- The layers inside are drawn into a separate picture; then the group's `effects` (relative to the group bounds, so `fade` and `crop` work on the group's edges), `opacity` and `rotate` (around the centre of the bounds) are applied, and the picture is composited at the group's place in the stack.
- Layers inside a group are ordinary layers: their ids are unique across the whole design [1108], they can be referenced from anywhere, and they can use `repeat` and `extends`.
- A group itself cannot have `anchor`, `repeat` or `extends` [1101]. Nesting deeper than 16 levels is [5001].
- Diagnostics inside a group use nested pointers, such as `/layers/2/layers/0/box/x`.

### 5.11 `divider`

A divider organises the layer list in the editor. It draws nothing and takes no part in rendering.

```json
{ "id": "stats_divider", "type": "divider", "label": "Monster stats" }
```

| Field | Kind | Default |
| --- | --- | --- |
| `id` | ident | required, unique like every layer id [1108] |
| `label` | string | the id; shown as the divider's title |
| `note` | string | |

- Any other field is [1101]. A divider has no bounds and cannot be referenced with `@` [3002] or extended [1112].
- Dividers may sit at the top level or inside groups; they do not count towards a group's bounds.

## 6. Expressions

### 6.1 Literals

- Numbers: `12`, `0.5`, `.5` is invalid. Optional unit suffix: `%`, `vw`, `vh`.
- Strings: `'single'` or `"double"` quotes, `\'` `\"` `\\` `\n` escapes. Single quotes avoid escaping inside JSON.
- Booleans: `true`, `false`.
- Colors: `#RRGGBB`, `#RRGGBBAA` (8-bit), `#RRRRGGGGBBBB`, `#RRRRGGGGBBBBAAAA` (16-bit). Hex digits are case-insensitive. Internally all colors are 16-bit RGBA; 8-bit values `v` become `v * 257`.

### 6.2 Units

| Unit | Means |
| --- | --- |
| `N%` | N percent of the canvas along the field's axis. Horizontal fields: `box.x`, `box.w`, `at.x`, a point's first value, `wrap`. Vertical fields: `box.y`, `box.h`, `at.y`, a point's second value. Anywhere else (`size`, `radius`, `stroke.width`...) `%` is [3006] |
| `Nvw`, `Nvh` | N percent of canvas width / height, valid in any number field |

`canvas.width` and `canvas.height` cannot use units (the canvas is being defined).

### 6.3 Names

| Name | Type | Meaning |
| --- | --- | --- |
| a param name | param's type | Card value or default |
| loop names | number / item | From `repeat` |
| `canvas.w`, `canvas.h` | number | Canvas size |
| `card.id` | text | The card's id |
| `render.index` | number | 0-based position of the card in its set |
| `render.date` | text | ISO date `YYYY-MM-DD`, chosen once by whoever starts the render |
| `@<layer_id>.<field path>` | field's type | The other layer's evaluated field, e.g. `@title.at.y`, `@bg.box.w`, `@bg.fill` |
| `@<layer_id>.bounds.<f>` | number | Final pixel bounds after anchor and layout: `left`, `top`, `right`, `bottom`, `w`, `h`, `cx`, `cy` |
| `list[n]`, `item.field` | | Indexing (0-based, out of range is [3102]) and field access |
| `list.Key`, `list["Key"]` | value field's type, or item | Lookup by key (6.3.1) |

#### 6.3.1 Lookup by key

A list whose item has a `text` field can be read by key. The key field is the item's first `text` field; `list.Key` and `list["Key"]` (any text expression in the brackets) find the first item whose key field equals the key, compared exactly (case-sensitive).

- When the item has exactly two fields (a key and a value, such as `{ "name": "text", "value": "number" }`), the lookup gives the value: `stats.Speed` is a number.
- Otherwise it gives the item: `rows.top.x`.
- After `.` a key may use upper case (`stats.Speed`); keys with spaces or other characters use brackets: `stats["Attack power"]`.
- A list without a `text` field cannot be looked up by key [3003]. A key no item has is [3104] at render time; the message lists the keys the card has.

```json
"params": { "stats": { "type": "list", "item": { "name": "text", "value": "number" }, "default": [] } }
"box": { "x": 20, "y": 40, "w": "stats.Speed * 2", "h": 12 }
"text": "Charm {stats['Charm']}"
```

Layer references always start with `@`, so params and layer ids live in separate namespaces and a param `background` can coexist with a layer `background`. Unknown names are [3002] with a hint. References between layers may point forward or backward; the core orders evaluation by dependency and reports cycles [3004]. Drawing order is always array order.

### 6.4 Operators

Highest precedence first:

| Operators | Operand types | Result |
| --- | --- | --- |
| `( )`, `f(...)`, `a.b`, `a[n]` | | |
| unary `-`, `not` | number / bool | |
| `* / %` | number | number. Division by zero is [3103] |
| `+ -` | number | number |
| `< <= > >=` | number | bool |
| `== !=` | same type on both sides | bool |
| `and` | bool | bool, short-circuit |
| `or` | bool | bool, short-circuit |
| `c ? a : b` | bool, then same type | right-associative |

`%` as an operator needs spaces or operands on both sides (`a % b`); `50%` directly after a number is the unit. There is no assignment, no string concatenation operator (use templates), and no implicit conversion: `'5' + 1` is [3003].

### 6.5 Functions

| Function | Signature |
| --- | --- |
| `min`, `max` | `(number, number, ...) -> number` |
| `clamp` | `(value, lo, hi) -> number` |
| `abs`, `floor`, `ceil` | `(number) -> number` |
| `round` | `(number, digits = 0) -> number` |
| `len` | `(list or text) -> number` |
| `upper`, `lower`, `trim` | `(text) -> text` |
| `fmt` | `(number, decimals) -> text`, e.g. `fmt(0.5, 2)` is `0.50` |
| `avg_color` | `(image) -> color`, average of opaque pixels |
| `mix` | `(color, color, t) -> color`, linear blend, `t` 0 to 1 |
| `with_alpha` | `(color, a) -> color`, `a` 0 to 1 |
| `rgb`, `rgba` | `(r, g, b[, a]) -> color`, channels 0 to 255, `a` 0 to 1 |

Calling an unknown function is [3002]; wrong argument count or types is [3003].

### 6.6 Templates (`text` and `path` fields)

Literal text with `{expression}` holes. `{{` and `}}` produce literal braces. Values convert as: number → shortest round-trip decimal (`5`, `0.5`, never `5.0`); bool → `true`/`false`; text unchanged; color → `#RRGGBBAA` (8-bit); list or item → [3003].

### 6.7 Determinism

The same project, card data and `render.date` always produce the same pixels in every build (WASM, CLI, server). There is no clock, randomness, network or file access inside expressions.

## 7. Card data

### 7.1 JSON (`*.cards.json`)

```json
{
  "format": 1,
  "design": "designs/monster.design.json",
  "cards": [
    { "id": "001", "title": "Shiro of the Immanity", "level": 5, "art": "assets/images/shiro.jpg" }
  ]
}
```

- `name` is an optional display name for the set.
- `id` is optional text; default is the 1-based index padded to 3 digits (`001`). Ids must be unique [2004] and must be safe as file names (`[A-Za-z0-9._-]`) [2005]. Output files are `<id>.png`.
- Every other key must be a declared param; unknown keys are warnings [2001] with a "did you mean" hint, and are ignored.
- Values must match the param type [2006]. Values are literals; expressions are not evaluated in card data.

### 7.2 CSV (`*.cards.csv`)

- RFC 4180: comma separated, `"` quoting, header row required. Header names are `id` and param names.
- The design comes from the manifest's `sets` entry for this file, or is passed explicitly (`yoshida render --design ...`).
- An empty cell means "use the default".
- `number`/`integer` cells use `.` as decimal separator; `bool` cells are `true`/`false`; `list` cells hold a JSON array.

## 8. Rendering model

- Coordinates are floating-point pixels, origin top-left, y down. Shapes and text are anti-aliased.
- Each layer is rendered to its own pixels, effects are applied, opacity is multiplied in, then it is composited onto the canvas with source-over on premultiplied 16-bit sRGB values (no linearization in v1).
- Anything outside the canvas is clipped silently. A layer entirely outside the canvas is a hint [3202].
- Output: PNG, 8-bit or 16-bit per channel, RGBA.

## 9. Diagnostics

Every problem is reported as `{ severity, code, file, path, span, message, hint }`. `path` is a JSON Pointer (`/layers/3/box/x`); `span` gives line and column in the file and, for expressions, the byte range inside the expression. Loading and checking report all problems; rendering starts only with zero errors. Codes are stable and never reused.

| Code | Severity | Meaning |
| --- | --- | --- |
| 1001 | err | JSON syntax error |
| 1101 | err | Unknown field |
| 1102 | err | Missing required field |
| 1103 | err | Wrong JSON type for the field's kind |
| 1104 | err | `format` missing |
| 1105 | err | Unsupported `format` version |
| 1106 | err | Param name collides with a reserved word or function |
| 1107 | err | Param has neither `default` nor `required` |
| 1108 | err | Duplicate or invalid layer id |
| 1109 | err | Polygon has fewer than 3 points |
| 1110 | err | Image `w` and `h` both `auto` |
| 1111 | err | `repeat` needs exactly one of `count` / `each` |
| 1112 | err | `extends` across different layer types (including a group), or of a divider |
| 1201 | err | File not found |
| 1202 | err | CSV syntax error |
| 1203 | err | Path escapes the project root |
| 2001 | warning | Card sets an unknown param |
| 2002 | err | Value outside `min`/`max`/`max_length` |
| 2003 | err | Required param missing |
| 2004 | err | Duplicate card id |
| 2005 | err | Card id not safe as a file name |
| 2006 | err | Card value has the wrong type, or is not an enum option |
| 3001 | err | Expression syntax error |
| 3002 | err | Unknown name or function |
| 3003 | err | Type mismatch or wrong function arguments |
| 3004 | err | Reference or `extends` cycle |
| 3005 | err | Reference to a repeated layer |
| 3006 | err | Unit not valid in this field |
| 3101 | err | Negative width or height (at render time) |
| 3102 | err | List index out of range (at render time) |
| 3103 | err | Division by zero (at render time) |
| 3104 | err | List lookup by a key no item has (at render time) |
| 3201 | warning | Text truncated by `max_lines` |
| 3202 | hint | Layer entirely outside the canvas |
| 3203 | warning | Text does not fit `max_width` / `max_height` even at `min_size` |
| 4001 | err | Image not found or unreachable (placeholder in preview) |
| 4002 | err | Image could not be decoded |
| 4003 | warning | Font lacks glyphs for some characters (drawn as boxes) |
| 4004 | err | Font name not declared in `fonts` |
| 4005 | warning | Font file missing or not a TrueType/OpenType font; the default font is used |
| 5001 | err | A limit was exceeded |

Default limits (the server may lower them): canvas 10000 x 10000 px, 500 layers after repeat expansion, 1000 iterations per repeat, images 50 megapixels, 10000 cards per set.

## 10. Versioning

`format` is an integer. A new major format adds a migration in the core; `yoshida migrate` rewrites files in place and keeps everything else byte-identical where possible. Adding optional fields with defaults does not bump the version.
