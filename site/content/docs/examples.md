+++
title = "Examples"
+++

The `examples/` folder holds six projects. Open them from the editor's project menu, or render them from the command line:

```sh
yoshida check examples/feature-tour
yoshida render examples/feature-tour --out out --date 2026-10-08
```

| Example | Shows | Card data |
| --- | --- | --- |
| `feature-tour` | Every layer type except divider, effects (`fade`, `find_edges`), a group, repeat (count and each), auto-shrink and justified text, rotation, expressions with `@layer` references, templates | JSON, two cards (`blue`, `gold`) |
| `gamecard-simple` | The simplest useful project: a manifest, a CSV card file, two fonts, `extends` | CSV, listed in `yoshida.json` |
| `cocktail` | A recipe card with a list param (ingredients), `extends` and an image loaded from a URL | JSON |
| `yugioh` | A full trading-card design converted from the old Python version: many params in groups, dividers in the layer list, a card frame, `extends`, attributes picked by a template path, a canvas that scales with a param | JSON |
| `board-game` | A printable A4 party board: a 40-tile ring as one repeated group with `translate`, design functions, an enum list field, a shared text size, `canvas.dpi`, a theme per card. See [Example: Board Game](@/docs/example-board-game.md) | JSON, three boards |
| `unit-test` | A minimal design used for tests | JSON, one empty card |

## feature-tour

The best place to learn by reading. It uses most expression features:

- `"fill": "mix(accent, #FFFFFF, 0.85)"` and `"color": "with_alpha(accent, 0.6)"`: color functions.
- `"x": "50% + (i - (level - 1) / 2) * 56"` with `repeat.count`: a centred row of stars.
- `"text": "{upper(title)}"` with `max_width` and `min_size`: a title that shrinks to fit.
- `"align": "justify"`, `wrap`, `max_lines`: body text that is cut with an ellipsis and warns.
- `"rotate": "@ribbon.rotate"`: a label that follows a ribbon.
- A `group` with `rotate` holding a circle and its number.
- `repeat.each` over a `list` param for the stats rows.

| | |
| --- | --- |
| ![feature-tour, blue card](../images/tour-blue.png) | ![feature-tour, gold card](../images/tour-gold.png) |

## gamecard-simple

```txt
gamecard-simple/
  yoshida.json
  designs/gamecard.design.json
  cards/drinking-game.cards.csv
  assets/fonts/...
```

The manifest pairs the CSV file with the design; CSV cannot name its design. See [Card Data](@/docs/card-data.md#csv-cards-csv).

![gamecard-simple](../images/gamecard.png)

## yugioh

Uses commercial fonts that are **not redistributable**, so the public web build leaves them out and the design falls back to the bundled font (warning 4005). See [Third-Party Notices](@/docs/third-party-notices.md). In a private bundle it renders as designed:

![The yugioh example in the editor](../images/builder-v03-dark-yugioh.png)

## board-game

A whole board per card, built from one list param. How it is built is on its own page: [Example: Board Game](@/docs/example-board-game.md).

![board-game, road-trip board](../images/board-game-road-trip.png)

## Making your own

Copy the example closest to what you need, rename the design and card files, and change them in the editor. Use `yoshida check` to validate and `yoshida fmt` to keep the JSON tidy. Start from [Getting Started](@/docs/getting-started.md).
