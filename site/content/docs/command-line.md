+++
title = "Command Line"
description = "Check projects, render cards and format files from a terminal or CI."
+++

The `yoshida` tool checks projects, renders cards and formats files. It never uses the network except to download `https://` images while rendering, and it can be run offline.

```txt
yoshida check  <project>...  [--set NAME] [--card ID] [--format text|json]
                          [--now YYYY-MM-DDTHH:MM:SSZ] [--utc-offset HOURS]
yoshida render <project>  [--set NAME] [--card ID] [--out DIR]
                          [--date YYYY-MM-DD] [--now YYYY-MM-DDTHH:MM:SSZ]
                          [--utc-offset HOURS] [--16bit] [--preview]
                          [--offline] [--pdf] [--crop-marks] [--svg]
                          [--vector] [--scale N] [--sheet COLSxROWS]
                          [--page a4|letter|...|WxH] [--gap MM] [--margin MM]
                          [--back SET[:ID]] [--duplex long|short]
                          [--format text|json]
yoshida fmt    <project or file>...  [--check]
yoshida version
```

`<project>` is a [project folder](@/docs/project-layout-and-manifest.md). `check` and `fmt` take several of them in one run; `render` takes one (more is a usage error). Run `yoshida` with no arguments (or `yoshida help`) to print the usage text.

## `yoshida check`

Loads the manifest, every design and every card file, and reports every problem. When loading found no errors, it then **evaluates every card without drawing it**, which finds the problems that depend on card data: the [layer limit](@/docs/repeat.md#the-layer-limit), a missing image file, an index or key that does not exist, a division by zero. `https://` images are not downloaded by `check`. `--set` and `--card` limit which cards are evaluated. `check` takes `--now` and `--utc-offset` as `render` does, so the expressions see the same `render.date` and `render.time`. It has no `--date`. For each set it prints the design, the card file and the number of cards, then a summary:

```txt
set tour: designs/tour.design.json, 2 card(s)
0 error(s), 0 warning(s), 0 hint(s), 2 card(s) checked
```

With several projects, `check` goes through them in the order given, and the text output has a `== <project> ==` line before each one. With `--format json` it writes one JSON object per project, one per line, each with a `"project"` field first. Every project is checked even when an earlier one has errors, and the exit status is the highest of them (1 if any project has errors, 2 for a usage error). A folder that cannot be opened counts as an error for that project and the others are still checked.

```sh
yoshida check examples/forge examples/poker
```

## `yoshida render`

Renders cards to PNG files at `<out>/<set>/<card id>.png`, or to [SVG files](#svg) or [one PDF per set](#pdf). A project with several sets (one per card file, see [Project Layout and Manifest](@/docs/project-layout-and-manifest.md)) renders all of them unless you pick one.

| Option              | Meaning                                                                                                                                                                               |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--set NAME`        | Render only this set. An unknown name lists the available sets and exits with status 2                                                                                                |
| `--card ID`         | Render only the card with this id (the card's `id` in the card data, such as `road-trip`, not its title or index). Combine it with `--set` when several sets have a card with that id |
| `--out DIR`         | Output folder. Default: `<project>/out`                                                                                                                                               |
| `--date YYYY-MM-DD` | Pins the date when `--now` is not given: `render.date` is this date, `render.time` is `00:00:00`, and `render.now` is that date at `00:00:00Z`. The utc offset is not applied. Ignored when `--now` is given. Pass it to make a render reproducible |
| `--now YYYY-MM-DDTHH:MM:SSZ` | The UTC instant of the render. `render.now` is this instant, and `render.date` and `render.time` are it shifted by the offset. Overrides `--date`. Default: the clock when the command starts. Pass it to make a render reproducible |
| `--utc-offset HOURS` | Offset from UTC for `render.date` and `render.time`: a number from -14 to 14, fractions allowed (`5.5`). Replaces `utc_offset` in `yoshida.json` for this run. Outside that range is a usage error (exit status 2). No effect with `--date` alone. See [Time zone](@/docs/project-layout-and-manifest.md#time-zone) |
| `--16bit`           | Write 16-bit-per-channel PNGs (default is 8-bit)                                                                                                                                      |
| `--preview`         | A missing or undecodable image becomes a placeholder and a warning instead of an error                                                                                                |
| `--offline`         | Do not download `https://` and `http://` images                                                                                                                                       |
| `--pdf`             | Write one PDF per set, `<out>/<set>.pdf`, one page per card, instead of PNG files. See [PDF](#pdf)                                                                                    |
| `--crop-marks`      | Put each card on a white sheet with crop marks at the trim line (`canvas.bleed` inside the edge). Works for PNG and PDF. With `--page`, the marks go around the grid instead, see [Print layout](#print-layout) |
| `--svg`             | Write one SVG file per card, `<out>/<set>/<card id>.svg`, instead of PNG files. See [SVG](#svg)                                                                                    |
| `--vector`          | With `--pdf`: draw the pages as vectors instead of images. See [PDF](#pdf)                                                                                                            |
| `--scale N`         | Render at N times the canvas size, 1 to 4 (default 1), for sharper print. The printed size stays the same: the PNG dpi is `canvas.dpi` times N and PDF pages keep their size. A side over 10000 pixels is error 5001. With `--svg` or `--vector` it is the resolution of the parts that stay pixels (default 2). See [Resolution](@/docs/saving-images-and-privacy.md#resolution) |
| `--sheet COLSxROWS` | Tile the cards of each set into one PNG per set, e.g. `10x7` for a tabletop simulator deck. See [Sheets](#sheets) |
| `--page SIZE`       | With `--pdf`: lay the cards out side by side on pages of this size, `a3`, `a4`, `a5`, `a6`, `letter`, `legal`, `tabloid` (each also with `-landscape`) or `WxH` in millimetres (`297x420`). See [Print layout](#print-layout) |
| `--gap MM`          | With `--page`: millimetres between neighbouring cards, 0 to 50 (default 0) |
| `--margin MM`       | With `--page`: the least room left at each edge of the page, 0 to 50 mm (default 5) |
| `--back SET[:ID]`   | With `--page`: a page of backs after each page of fronts, showing the first card of `SET` (or card `ID`) behind every card |
| `--duplex EDGE`     | With `--back`: the edge your duplex printer flips the sheet on, `long` (default) or `short` |
| `--format json`     | Print one JSON document (diagnostics, sets, written files, files with errors) instead of text                                                                                         |

### Where the files go

The output folder is named after the **set**. For a JSON card file that is not listed in `yoshida.json`, the set name is the card file's name up to the first dot (`cards/boards.cards.json` is set `boards`; `deck.v2.cards.json` is set `deck`). The `name` field inside the card file does not change it. A set listed in the manifest uses its `name` there. See [Project Layout and Manifest](@/docs/project-layout-and-manifest.md#sets).

```sh
yoshida render examples/board-game --card road-trip --out out
# wrote out/boards/road-trip.png (4961 x 3508)
```

### Errors while rendering

Rendering starts only when loading reported zero errors. If loading reports errors, nothing is written and the tool says so.

Some errors can only be found while a card is evaluated, because they depend on its values: a missing image (4001), an index out of range (3102), more than 500 visible layers (5001, see [Repeat](@/docs/repeat.md#the-layer-limit)). `yoshida check` finds them before you render. When rendering, a layer that fails is skipped and the rest of the card is still drawn and written, and the tool says so:

```txt
wrote out/deck/bigshown.png (400 x 300) with 1 error(s): parts of the card are missing
1 error(s), 0 warning(s), 0 hint(s), 3 card(s) rendered, 1 with errors
```

The exit status is 1. With `--format json`, the files are listed in `written` and again in `with_errors`, and the `card` field of each diagnostic names the card.

### PDF

```sh
yoshida render examples/board-game --out out --pdf
# wrote out/boards.pdf (3 page(s))
```

- One page per card, in card order; `--card` and `--set` pick cards as for PNG.
- The page size is the canvas at `canvas.dpi` (a 2340 px wide card at 200 dpi is 297 mm). Without `canvas.dpi`, one canvas pixel is one point (1/72 inch). `--scale` does not change it: the page holds a sharper image.
- The card is the BleedBox, and the TrimBox is `canvas.bleed` inside it, so print dialogs and print shops know where to cut. With `--crop-marks` the page grows by a margin with the marks.
- The card is stored as an 8-bit image with transparency.
- With `--vector` the card is drawn as vectors instead, as in an [SVG file](#svg): shapes and text stay sharp at any zoom, and the file is usually much smaller. Page size, boxes and crop marks are the same as for the image PDF, and `--scale` sets the resolution of the parts that stay pixels (default 2).

```sh
yoshida render examples/poker --set numbers --out out --pdf --vector
# wrote out/numbers.pdf (40 page(s))
```

### Print layout

`--page` turns the PDF into sheets to print at home or at a copy shop: the cards of each set side by side on pages of a paper size, instead of one page per card.

```sh
yoshida render examples/poker --pdf --vector --page a4 --back back --crop-marks
# wrote examples/poker/out/numbers.pdf (40 card(s) of 63.5 x 88.9 mm on 10 page(s), 3x3 per page, backs for flip on long edge)
#   print at 100% (actual size), not "fit to page": the cards are 63.5 x 88.9 mm
```

- **Pages**: `a3` (297 x 420 mm), `a4` (210 x 297 mm), `a5` (148 x 210 mm), `a6` (105 x 148 mm), `letter` (8.5 x 11 in), `legal` (8.5 x 14 in) or `tabloid` (11 x 17 in), each also with `-landscape`, or any size as `WxH` in millimetres, 20 to 2000 each. The page is the size given, never turned to fit more cards.
- **Scale**: cards are placed at their printed size, the trim size from `canvas.dpi` (a 750 x 1050 px design at 300 dpi is 63.5 x 88.9 mm; without `canvas.dpi`, a pixel is a point). The tool prints that size. Print the PDF at 100 % ("actual size"), never "fit to page" or "shrink to fit": scaling makes the cards the wrong size and the crop marks no longer match.
- **Grid**: as many cards as fit inside `--margin` (default 5 mm, the edge most printers cannot print on), `--gap` millimetres apart (default 0), centred on the page. Cards keep their printed size (see `canvas.dpi`); a card larger than the page inside the margins is an error. The grid is set by the first card; a card of another size is centred on its place, cut to it, and the tool warns.
- **Bleed**: the cards are placed by their trim size (`canvas.bleed` inside the edge). The bleed shows at the outside of the grid and up to half the gap between cards, so neighbours never cover each other. With no gap, cards meet at the trim line and the cuts are shared.
- **Crop marks**: with `--crop-marks`, short lines in the margin above, below, left and right of the grid at every trim line, for cutting with a guillotine or a ruler. They start 2 mm outside the bleed and are cut short at the edge of the page.
- **Backs**: `--back back` puts the first card of the set `back` behind every card (`--back back:blue` picks the card `blue`). After each page of fronts comes a page with one back for each card on it, placed so that each back lands behind its front when the pages are printed on both sides of the sheet. The back is stored once, however many pages show it. The back set is left out of the sets that are printed unless `--set` names it.
- **Duplex**: with `--duplex long` (the default), the backs of a portrait page are mirrored left to right, for a printer that turns the sheet over its long edge, like the page of a book. With `--duplex short` the rows are mirrored top to bottom and each back is turned 180°, so a cut card still shows its back the right way up when turned over sideways. On a landscape page the two swap. Print a test sheet first: hold it against the light to check that fronts and backs line up, and print at 100 % (no "fit to page").
- `--vector` draws the cards as vectors, as for other PDFs; without it each card is an image at `--scale`. `--card` and `--set` pick cards as usual.

### SVG

```sh
yoshida render examples/poker --set courts --card JC --out out --svg
# wrote out/courts/JC.svg (750 x 1050)
```

- One SVG file per card. With `canvas.dpi` its size is the printed size in millimetres, otherwise the canvas size in pixels; the `viewBox` is the canvas in pixels either way.
- Shapes are paths with true curves. Text becomes the outlines of its letters: it looks the same everywhere without the font, but it cannot be selected or searched.
- Images are embedded as PNG or JPEG data, see [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md#svg-and-vector-pdf).
- Rotation, opacity and the `crop` and `fade` [effects](@/docs/effects.md) stay vectors. The filters `sharpen`, `detail`, `edge_enhance` and `find_edges` have no vector form: a layer or group with one of them is drawn as pixels at the export resolution (`--scale`; 2x when not given) and embedded as an image.
- `--crop-marks` and `--16bit` do not apply to SVG files.
- Any viewer draws anti-aliasing and scaled images a little differently from yoshida's own renderer, so an SVG is very close to the PNG, not identical. See [Known Gaps](@/docs/known-gaps.md#output).

### Sheets

`--sheet 10x7` tiles the cards of each set left to right, top to bottom into one PNG, `<out>/<set>.png`, for deck images in a tabletop simulator. A set with more cards than one sheet holds is written as `<set>-1.png`, `<set>-2.png` and so on. Every sheet has the full grid (empty cells are transparent), and the cell size is the size of the first card. `--scale` and `--card` work as usual; `--sheet` cannot be combined with `--pdf` or `--svg`. A sheet may be at most 20000 pixels per side.

```sh
yoshida render my-game --sheet 10x7
# wrote my-game/out/actions.png (7500 x 7350, 10x7 sheet, 70 card(s))
```

The editor makes the same sheets: **Export…**, then **Sheet** ([export dialog](@/docs/builder.md#export-dialog)). So does the server, with `"sheet"` in a [render request](@/docs/server-api.md).

### Images from the web

Image paths that are `https://` or `http://` URLs are downloaded once per run. Use `--offline` to forbid that (a URL is then an error 4001, or a placeholder with `--preview`). Behind a TLS-intercepting proxy the download can fail; use `--offline` with local files.

### Reproducible output

The same project, card data, `--now` (or `--date`) and offset give the same pixels on every platform and in every front end, and the same bytes for SVG and PDF files. Without `--now` or `--date`, the render uses the clock when the command starts, so `render.date` is today's date in the offset time zone.

### JSON output

```sh
yoshida render my-cards --format json
```

```json
{
	"diagnostics": [],
	"sets": [
		{
			"name": "core",
			"design": "designs/monster.design.json",
			"cards": 12,
			"ok": true
		}
	],
	"written": ["my-cards/out/core/001.png"],
	"with_errors": []
}
```

The shape of each diagnostic is described in [Diagnostics](@/docs/diagnostics.md#json-shape).

## `yoshida fmt`

Rewrites JSON files into the canonical layout (the same rules the editor uses; see [Formatting and Schemas](@/docs/formatting-and-schemas.md)). Give it one or more project folders or single files.

```sh
yoshida fmt examples            # rewrite
yoshida fmt examples --check    # list files that would change, change nothing
yoshida fmt designs/a.design.json yoshida.json   # several files
```

The summary counts the files of all the paths together. With `--check` the exit status is 1 if any file is not formatted (or a path cannot be read), which is what [CI](@/docs/ci-and-deployment.md) uses.

## Limits

`check` and `render` read the environment variables `YOSHIDA_MAX_LAYERS`, `YOSHIDA_MAX_REPEAT`, `YOSHIDA_MAX_CANVAS`, `YOSHIDA_MAX_IMAGE_MP` and `YOSHIDA_MAX_SET_CARDS`, which raise (or lower) the [limits](@/docs/limits-and-versioning.md#raising-a-limit) of a design. Each takes a whole number or the word `unlimited`; a value that is neither is a usage error.

```sh
YOSHIDA_MAX_LAYERS=2000 yoshida render my-game
```

## Exit status

| Status | Meaning                                                                                                   |
| ------ | --------------------------------------------------------------------------------------------------------- |
| 0      | No errors (warnings and hints do not count)                                                               |
| 1      | Errors were reported, or `fmt --check` found unformatted files, or the project folder could not be opened |
| 2      | Usage error (bad option, unknown command, unknown set)                                                    |

## Examples

```sh
# render the first card of a set, 16-bit, fixed date
yoshida render my-cards --set core --card 001 --16bit --date 2026-01-01 --out build

# render at a fixed instant, shown in UTC+2 (render.date and render.time)
yoshida render my-cards --now 2026-01-01T22:30:00Z --utc-offset 2 --out build

# validate in a script and fail the build on errors
yoshida check my-cards || exit 1
```
