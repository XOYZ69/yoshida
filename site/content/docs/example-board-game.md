+++
title = "Example: Board Game"
+++

`examples/board-game` is a printable party board game: 40 tiles in a ring from START to FINISH, special tiles, a title and rules panel with a tile guide, dice and pawns. The design is the board, and every card in the card file is a different board with its own tiles and color theme.

```sh
yoshida check examples/board-game
yoshida render examples/board-game --out out --date 2026-10-09
# wrote out/boards/road-trip.png (2340 x 1654)
# wrote out/boards/moon-base.png (2340 x 1654)
# wrote out/boards/beach-party.png (2340 x 1654)
```

![The road-trip board](../images/board-game-road-trip.png)

## Files

```txt
board-game/
  designs/board.design.json
  cards/boards.cards.json     (set "boards": road-trip, moon-base, beach-party)
  assets/fonts/Bebas-Regular.ttf
```

There is no `yoshida.json`: the JSON card file names its design, and the set is named after the file (`boards`). See [Command Line](@/docs/command-line.md#where-the-files-go).

## How it is built

- **Canvas**: 2340 x 1654 px with `"dpi": 200`, which is A4 landscape. PNG and PDF files carry the size, so the board prints at 100 % without guessing. `yoshida render examples/board-game --pdf` gives one PDF with a page per board.
- **Tiles** come from a [list param](@/docs/params.md#lists) `tiles` with the item fields `kind`, `text` and `n`. `kind` is an [enum item field](@/docs/params.md#item-fields) (`start`, `finish`, `plain`, `safe`, `skip`, `back`, `forward`, `shortcut`, `dare`, default `plain`), so a typo in card data is error 2006. The list runs clockwise from the top-left corner; the first item is START, the last FINISH. `n` is the number of steps for `back` and `forward` and the target tile for `shortcut`.
- **One tile is one repeated group.** The group `tile` [repeats](@/docs/layer-group.md#repeat) over `tiles`, and its `translate` puts each iteration at its place in the ring with two [functions](@/docs/expressions-constants-and-functions.md), `tile_x(i)` and `tile_y(i)` (13 x 9 tiles of 170 px). The layers inside use tile coordinates, 0 to 170, and read their own tile's values (`t.kind`, `t.text`).
- **A hidden base layer**: inside the tile, `tile_base` has `"visible": false` and holds the box and radius. `tile_shadow` and `tile_bg` [extend](@/docs/extends.md#a-hidden-base-layer) it and set `visible` back to `true`.
- **Icons**: each tile kind has a polygon icon with `"visible": "t.kind == 'skip'"` and so on, inside the group `tile_icon`. Its `translate` moves the icon left when the tile also shows a number, using the function `has_n(t.kind)`.
- **Tile kinds**: the background color is a chain of ternaries over `t.kind` and the `c_*` color params.
- **Text** shrinks to fit the tile (`wrap`, `max_width`, `max_height`, `min_size`), and `"shrink_group": "tile_text"` gives every tile the same size, the smallest any tile needs. See [Layer: text](@/docs/layer-text.md#auto-shrink).
- **Themes**: the `c_*` color params (paper, ink, frame, panel, text, accent, and one per tile kind) are grouped as "Theme colors", so a card is a theme.
- **Rules** are a `text` param whose default contains JSON newlines (`"1. ...\n2. ..."`), which become line breaks. See [line breaks in values](@/docs/expressions-templates.md#line-breaks-in-values).
- **The tile guide** repeats over a second list param, `legend`, whose `kind` field is an enum too.

The design is 585 lines after `yoshida fmt` and can be edited by hand or in the editor.

## Ideas to take it further

- **Links between tiles.** A shortcut tile can draw an arrow to its target with an [indexed reference](@/docs/repeat.md#reading-one-iteration) and an open polygon with `"arrow": "end"`: `[["@tile_bg[i].bounds.cx", "@tile_bg[i].bounds.bottom"], ["@tile_bg[t.n - 1].bounds.cx", "@tile_bg[t.n - 1].bounds.top"]]`, dashed with `"dash": [10, 6]`. The example does not, because the arrows would cross the rules panel.
- **Symbol glyphs instead of polygons.** Arrows, stars and dice faces now come from the bundled symbol font when the layer font lacks them, so `"text": "★"` works with Bebas.
- **Boards that share a layout.** Give `tiles` a default list and let each card change only some tiles: `"tiles": { "11": { "kind": "safe" } }`. See [Params](@/docs/params.md#changing-single-items-of-the-default).
- **Layer budget.** A tile draws 6 to 8 visible layers (the tile group, shadow, background, number, text, the icon group and the icon or number on special tiles), about 330 per card. The limit is 500 visible layers per card; `yoshida check` reports cards over it. See [Repeat](@/docs/repeat.md#the-layer-limit).
