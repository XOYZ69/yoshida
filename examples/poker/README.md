# Poker deck

A complete deck of playing cards: 52 cards, two jokers (red and black) and a card back, in four designs.

```sh
yoshida check examples/poker
yoshida render examples/poker --out out --date 2026-10-11
yoshida render examples/poker --out out --pdf   # one PDF per set
```

Each card is 750 x 1050 px at 300 dpi, the usual poker size of 63.5 x 88.9 mm (2.5 x 3.5 in), with transparent rounded corners.

| Set | Design | Cards |
| --- | --- | --- |
| `numbers` | `designs/number.design.json` | Ace to 10 in four suits, ids `AS` ... `10C` |
| `courts` | `designs/court.design.json` | Jack, queen and king in four suits, ids `JS` ... `KC` |
| `jokers` | `designs/joker.design.json` | `joker-red`, `joker-black` |
| `back` | `designs/back.design.json` | `back` |

What it shows:

- **Several designs in one project**: each card file names its design; `yoshida.json` lists the sets so they render in deck order with short names.
- **`extends`**: the bottom-right corner index extends the top-left one and only changes its position and turn. Every pip extends one hidden `pip` layer; the ace's ring layers extend each other.
- **Design functions**: `side_n`, `mid_n`, `side_t` and `mid_t` place the pips for every rank from 2 to 10; `flip` turns the lower pips upside down; `glyph` picks the suit symbol.
- **Repeated groups**: the court portrait is one group drawn twice, the second time turned 180 degrees, so the card reads the same both ways up. The back's lattice is a nested repeat.
- **Polygon shapes and points**: crowns, the jester cap, stars and diamonds.
- **Params for the whole deck**: `paper`, `red`, `black` and `gold` in every design, `color` and `deck_name` on the back, an optional `title` for court cards.
- **Symbol fallback**: the suit symbols come from the bundled symbol font.

Fonts: DM Serif Display and Cinzel Decorative, both under the SIL Open Font License (see `assets/fonts/*-license.txt`).
