## How yoshida works

A **project** is a folder. A **design** (`designs/<name>.design.json`) is a canvas with params and a list of layers. **Card data** (`cards/<name>.cards.json` or `.cards.csv`) is one row of param values per card. A **set** is one card file rendered with one design; `yoshida render` writes `<out>/<set>/<card id>.png`.

- Every JSON file has `"format": 1`. Plain JSON: no comments, no trailing commas; any object takes a `"note"` for comments.
- Paths in project files are relative to the project root, with `/`.
- A JSON card file names its design (`"design": "designs/x.design.json"`). A CSV card file must be listed in a set of `yoshida.json`. A design no set uses renders one card with all defaults.
- A card may only set params the design declares (an unknown one is warning 2001). A param needs `default` or `"required": true`.
- Layers are drawn in array order: the first is at the bottom. Layer ids are unique in the whole design, groups included.

## Rules that are easy to get wrong

- **Expression or template.** Number, color and bool fields take a JSON value or an expression in a string: `"w": "canvas.w - 2 * margin"`. Text fields (`text`, `src`, `logo_src`) are templates: literal text with `{expression}` holes, `"text": "Level {level}"`. A bare name in a template is literal text; in an expression, text needs quotes: `"visible": "kind == 'spell'"`.
- **No text concatenation.** `+` only adds numbers. Build text in a template, or with `join`, `replace`, `fmt`.
- **Logic is words:** `and`, `or`, `not`, `==`, `!=`, `c ? a : b`. There is no `&&`, `||`, `!`, `^` or `1e3`. Put spaces around `%`.
- **Colors** are `#RRGGBB` or `#RRGGBBAA`, bare in an expression: `"fill": "mix(accent, #FFFFFF, 0.5)"`.
- **Position.** `rect`, `ellipse`, `image`, `qr` and `barcode` use `box` (`x`, `y`, `w`, `h`); `text` uses `at` (`x`, `y`). `anchor` says which point of the layer that position is (default `top-left`; `center` centres it there). `polygon` points are absolute coordinates, unless it uses a preset `shape`, which takes `box` and `anchor`.
- **Per-card canvas.** A card may set `_width`, `_height`, `_dpi` and `_bleed` (JSON keys, CSV columns) to replace the design's canvas size, dpi and bleed for that card; absent ones inherit. `canvas.w`, `canvas.h` and `%` follow the card's size. Plain numbers, not expressions.
- **Units.** Plain numbers are pixels. `50%` is half the canvas along the field's axis, `10vw` and `10vh` are percent of the canvas width and height.
- **References.** `@id.bounds.bottom` reads another layer's final box (`left`, `top`, `right`, `bottom`, `w`, `h`, `cx`, `cy`), `@id.<field>` an evaluated field. They may point forward or backward; a cycle is error 3004. A repeated layer needs an index from outside: `@id[2].bounds.left`.
- **Text size.** `max_width`, `max_height` and `min_size` shrink text to fit (`min_squeeze` first narrows the letters sideways); `wrap` breaks lines at a width. Long card texts need one of them.
- **Text markup.** With `"markup": true` a text may use `<b>`, `<i>` and `{icon:name}`; icons come from the design's `"icons": "assets/icons/*.svg"` pattern.
- **Groups.** A group has no box of its own. `translate` moves its layers and makes their coordinates relative to it; `layout` places its children in a row or column by their measured size; `repeat` draws it once per iteration; `include` takes the layers from a component file.
- **Reuse.** `extends` copies another layer of the same type and overrides the fields given (every inherited field, `gradient` included). `consts` are named expressions; `functions` take arguments. Constants cannot call the design's functions.
- **Check your work.** `yoshida check <project>` reports every problem with file, line, code and a hint; `yoshida fmt <project>` writes the canonical layout that `fmt --check` in CI expects.
