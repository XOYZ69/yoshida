# Party board game

A printable party board: 40 tiles in a ring from START to FINISH, special tiles (safe zone, skip, go back N, go forward N, shortcut, dare), a centred title and rules panel with a tile guide, and a theme per card. The design is the board; every card is a different board.

```sh
yoshida check examples/board-game
yoshida render examples/board-game --out out --date 2026-10-09
yoshida render examples/board-game --out out --pdf      # out/boards.pdf, one page per board
```

Each board is A4 landscape at 200 dpi (2340 x 1654 px, `canvas.dpi` is set, so the PNG and the PDF carry the size): print it at 100 % scale.

- Tiles come from the `tiles` list param: 40 items `{ "kind", "text", "n" }`, clockwise from the top-left corner (first item = START, last = FINISH). `kind` is an enum field (`start`, `finish`, `plain`, `safe`, `skip`, `back`, `forward`, `shortcut`, `dare`), so a typo in card data is an error; `n` is the step count (back, forward) or the target tile number (shortcut).
- One tile is the repeated group `tile`: `repeat` over `tiles`, `translate` from the functions `tile_x(i)` and `tile_y(i)`, and the layers inside drawn in tile coordinates (0 to 170). For another board size change those two functions.
- The tile's icon is the group `tile_icon`, moved left by its `translate` when the tile shows a number (`has_n(t.kind)`).
- Colors are `c_*` params (paper, ink, frame, panel, text, accent and one per tile kind), so a card is a theme.
- Tile text shrinks to fit (`max_width`, `max_height`, `min_size`), and `shrink_group` gives every tile the same size.
- Font: Bebas (see `assets/fonts/Bebas-Regular-license.txt`).
