+++
title = "Project Layout and Manifest"
description = "A project folder, its paths and the yoshida.json manifest."
+++

A **project** is a folder. All paths inside project files are relative to the project root, use `/` as separator and must not escape the root (a `..` that climbs above the root is error 1203).

```txt
my-cards/
  yoshida.json                 project manifest (optional)
  designs/<name>.design.json   designs
  cards/<name>.cards.json      card data (JSON)
  cards/<name>.cards.csv       card data (CSV)
  assets/...                   images and fonts, any structure
  .yoshida/                    caches, never committed
```

The tool finds files by their endings (`.design.json`, `.cards.json`, `.cards.csv`), wherever they are in the project, so the `designs/` and `cards/` folders are a convention, not a requirement. The editor creates and uses them.

All files are UTF-8 without a byte-order mark. JSON follows RFC 8259: no comments and no trailing commas. Use the `note` field (any object accepts one) for comments.

Every JSON file has `"format": 1`. Missing is error 1104, an unsupported version is 1105. A `"$schema"` key is allowed at the top of a file and ignored (see [Formatting and Schemas](@/docs/formatting-and-schemas.md)).

## Sets

A **set** is one card file rendered with one design. Output files are written to `<out>/<set name>/<card id>.png`.

How sets are found:

1. Every entry in the manifest's `sets` array is a set.
2. Every `*.cards.json` file not already listed names its own design (`"design": "designs/x.design.json"`) and becomes a set, named after the file (`monster.cards.json` becomes `monster`; the name is the file name up to the first dot).
3. A `*.cards.csv` file must be listed in the manifest, because CSV cannot name its design. An unlisted CSV file is warning 1102.
4. A design that no set uses becomes a set with no card data: it renders **one** card with all defaults. That is how the hello-world project in [Getting Started](@/docs/getting-started.md) works.

## The manifest `yoshida.json`

Optional. Needed for CSV card data and for naming sets explicitly.

```json
{
  "format": 1,
  "name": "My Cards",
  "sets": [
    { "name": "core", "design": "designs/monster.design.json", "cards": "cards/core.cards.csv" }
  ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `format` | yes | `1` |
| `name` | no | Display name of the project |
| `note` | no | Comment |
| `sets` | no | Array of sets, below |
| `utc_offset` | no | Hours from UTC for `render.date` and `render.time`: a number from -14 to 14, fractions allowed. Default `0`. See [Time zone](#time-zone) |

| Set field | Required | Meaning |
| --- | --- | --- |
| `design` | yes | Path to the design file |
| `cards` | no | Path to a `.cards.json` or `.cards.csv` file. Without it the set renders one card with defaults |
| `name` | no | Set name, used for the output folder and `--set`. Default: `set1`, `set2`, ... by position |

Unknown manifest fields are error 1101 with a "did you mean" hint. A path that leaves the project is 1203; a missing file is 1201.

## Time zone

`utc_offset` sets the project's time zone for the expressions `render.date` and `render.time`, as a **fixed offset in hours** from UTC. `render.now` is not affected: it is always UTC.

```json
{
  "format": 1,
  "utc_offset": 5.5
}
```

- The default is `0`, UTC. A value outside -14 to 14 is error 1103 when the project loads.
- A fixed offset does not follow daylight saving time, and named zones such as `Europe/Berlin` are not supported. For a zone with summer time, change the number when the clocks change (for example `2` in summer and `1` in winter for Central European Time).
- In the editor, the project settings show the offset with a **use my browser's offset** button, which fills in the offset of the browser's time zone. Previews use the current time, and an export uses the time it started.
- On the command line, `--utc-offset HOURS` replaces the value for one run. See [Command Line](@/docs/command-line.md#yoshida-render).

The functions that use the date and time are on [Dates and times](@/docs/expressions-functions-dates.md).

## Assets

Images and fonts can live anywhere. Reference them by project path, for example `"src": "assets/images/art.png"` or `"fonts": { "body": "assets/fonts/Body.ttf" }`. Paths in image fields can also be templates (`"src": "assets/{card_type}.png"`) or `https://` URLs. See [Layer: image](@/docs/layer-image.md) and [Designs](@/docs/designs.md).

## Several designs in one project

Put each design in `designs/`, give each its own card file, and the project has one set per pair. The editor's **+ Design** button creates a blank design together with its card file. The **Design** picker in the toolbar switches between them.

## `.yoshida/`

Reserved for caches. Do not commit it.
