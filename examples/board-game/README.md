# Party board game

A printable party board: 40 tiles in a ring from START to FINISH, special tiles (safe zone, skip, go back N, go forward N, shortcut, dare), a centred title and rules panel with a tile guide, and a theme per card. The design is the board; every card is a different board.

```sh
yoshida check examples/board-game
yoshida render examples/board-game --out out --date 2026-10-09
```

Each PNG is A4 landscape at 200 dpi (2340 x 1654 px): print it at 100 % scale.

- Tiles come from the `tiles` list param: 40 items `{ "kind", "text", "n" }`, clockwise from the top-left corner (first item = START, last = FINISH). `kind` is one of `start`, `finish`, `plain`, `safe`, `skip`, `back`, `forward`, `shortcut`, `dare`; `n` is the step count (back, forward) or the target tile number (shortcut).
- Colors are `c_*` params (paper, ink, frame, panel, text, accent and one per tile kind), so a card is a theme.
- Tile text shrinks to fit (`max_width`, `max_height`, `min_size`).
- Font: Bebas (see `assets/fonts/Bebas-Regular-license.txt`).
- The ring is built with one `repeat` over the tiles and a grid position computed from the index. For another board size change the ring formulas in the `tile_*` layers (13 x 9 tiles of 170 px).
