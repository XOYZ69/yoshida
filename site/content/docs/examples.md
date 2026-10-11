+++
title = "Examples"
description = "The two example projects and what each one shows."
+++

The `examples/` folder holds two projects. Open them from the editor's project menu, or render them from the command line:

```sh
yoshida check examples/poker
yoshida render examples/poker --out out --date 2026-10-11
```

| Example | Shows | Card data |
| --- | --- | --- |
| `poker` | A full deck of 52 cards, two jokers and a card back. Four designs in one project, `extends` for mirrored corner indices and pips, design functions that place the pips for every rank, a repeated group turned 180 degrees for double-ended court cards, a nested repeat for the back pattern, a manifest that orders the sets. See [Example: Poker Deck](@/docs/example-poker.md) | JSON, four card files listed in `yoshida.json` |
| `board-game` | A printable A3 party board: a 40-tile ring as one repeated group with `translate`, design functions, an enum list field, a shared text size, `canvas.dpi` and `canvas.bleed`, a theme per card. See [Example: Board Game](@/docs/example-board-game.md) | JSON, four boards |

Every font in the examples is under the SIL Open Font License or a free font license and may be shared; see [Third-Party Notices](@/docs/third-party-notices.md).

## poker

One project, four designs: number cards (ace to 10), court cards (J, Q, K), the joker and the back. How it is built is on its own page: [Example: Poker Deck](@/docs/example-poker.md).

![poker, a selection of cards](../images/poker-deck.png)

## board-game

A whole board per card, built from one list param. How it is built is on its own page: [Example: Board Game](@/docs/example-board-game.md).

![board-game, road-trip board](../images/board-game-road-trip.png)

## Making your own

Copy the example closest to what you need, rename the design and card files, and change them in the editor. Use `yoshida check` to validate and `yoshida fmt` to keep the JSON tidy. Start from [Getting Started](@/docs/getting-started.md).
