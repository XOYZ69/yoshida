# Party board game

A printable party board: 40 tiles in a ring from START to FINISH, special tiles (safe zone, skip, go back N, go forward N, shortcut with a ghost arrow, dare), a centred title and rules panel with a tile guide, dice and pawns. The design is the board, and every card is a different board.

```sh
yoshida check examples/board-game
yoshida render examples/board-game --out out --date 2026-10-11
yoshida render examples/board-game --out out --pdf --crop-marks   # print sheets
```

Each board is A3 landscape at 300 dpi (4961 x 3508 px, 420 x 297 mm, 3 mm bleed): print it at 100 % scale.

Cards: `road-trip` (uses every default of the design), `road-trip-night` (the same board with a dark theme and only five tiles changed), `moon-base` and `beach-party` (their own tiles and themes).

What it shows:

- **Constants and functions**: `tile`, `cols`, `rows`, `ox`, `oy` and friends are `consts`; `ring_col(i)`, `ring_row(i)`, `tile_x(i)`, `kind_color(k)`, `has_n(k)` and `pip(face, k)` are `functions`. Resize the ring by changing `cols` and `rows`.
- **Repeated groups with `translate`**: one `tile` group per list item, `legend_row` and `rule` per list item, `dice`, `die_pips` (3 x 3 grid, pips shown by `pip()`), `pawns`, `title_stars`, `stripes`. Layers inside use local coordinates.
- **Indexed references**: `@tile_bg[t.n - 1]` gives the target tile of a shortcut, and `rule_measure` stacks the rules by reading the previous iteration.
- **Auto-shrink with `shrink_group`**: every tile label uses the same size.
- **Polygon shapes and arrows**: `shape` presets (arrow, chevron, star, triangle), a dashed open polygon with `"arrow": "end"` for the shortcut links, and text outlines (`stroke`) on the title.
- **Symbol glyphs**: the `★` in the subtitle comes from the bundled symbol font, Bebas has none.
- **Params**: enum list-item fields (`kind`), a bool (`show_links`), a list default with single-item overrides on `road-trip-night` (`"tiles": { "4": { ... } }`), param groups, a translucent panel through which the shortcut arrows show.
- **Print**: `canvas.dpi`, `canvas.bleed`, `--pdf`, `--crop-marks`.

Font: Bebas (see `assets/fonts/Bebas-Regular-license.txt`).
