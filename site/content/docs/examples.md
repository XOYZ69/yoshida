+++
title = "Examples"
description = "The four example projects and what each one shows."
+++

The `examples/` folder holds four projects. Open them from the editor's project menu, or render them from the command line:

```sh
yoshida check examples/poker
yoshida render examples/poker --out out --date 2026-10-11
```

| Example | Shows | Card data |
| --- | --- | --- |
| `poker` | A full deck of 52 cards, two jokers and a card back. Four designs in one project, `extends` for mirrored corner indices and pips, design functions that place the pips for every rank, a repeated group turned 180 degrees for double-ended court cards, a nested repeat for the back pattern, a manifest that orders the sets, gold gradients. See [Example: Poker Deck](@/docs/example-poker.md) | JSON, four card files listed in `yoshida.json` |
| `board-game` | A printable A3 party board: a 40-tile ring as one repeated group with `translate`, design functions, an enum list field, a shared text size, row and column layout, bold in the rules, `canvas.dpi` and `canvas.bleed`, a theme per card. See [Example: Board Game](@/docs/example-board-game.md) | JSON, four boards |
| `cocktails` | Recipe cards, a menu and a shopping list at 600 dpi: an ingredient catalog as a list param, sums through chained hidden layers, seven glasses drawn from one width function, a drink color mixed from the ingredients and drawn as a gradient, bold alcoholic ingredients on the menu, a QR code per card | JSON, four card files listed in `yoshida.json` |
| `forge` | A small engine-builder card game and the shortest tour of the newer features: `{icon:name}` and `<b>` in card text, SVG art and icons, row layout for cost coins and a pill that fits its text, gradients, rounded and hexagon-clipped images, an optional image with a placeholder, an effect panel shared as a component, a QR code with a logo, and `--sheet` for deck images | JSON, two card files listed in `yoshida.json` |

Every font in the examples is under the SIL Open Font License or a free font license and may be shared; see [Third-Party Notices](@/docs/third-party-notices.md).

## poker

One project, four designs: number cards (ace to 10), court cards (J, Q, K), the joker and the back. How it is built is on its own page: [Example: Poker Deck](@/docs/example-poker.md).

![poker, a selection of cards](../images/poker-deck.png)

## board-game

A whole board per card, built from one list param. How it is built is on its own page: [Example: Board Game](@/docs/example-board-game.md).

![board-game, road-trip board](../images/board-game-road-trip.png)

## cocktails

Twenty-six recipe cards with a matching back, four menu pages and a shopping sheet, all from one ingredient catalog. `examples/cocktails/README.md` explains how the sums, the mixed drink color and the alcohol-free switch work.

## forge

Four cards that use the features made for card games: text with icons, rows that measure their content, gradients, clipped and optional images and a shared component. `examples/forge/README.md` lists which card shows which feature. For a deck image per set, as tabletop simulators want it:

```sh
yoshida render examples/forge --out out --sheet 10x7
```

## Making your own

Copy the example closest to what you need, rename the design and card files, and change them in the editor. Use `yoshida check` to validate and `yoshida fmt` to keep the JSON tidy. Start from [Getting Started](@/docs/getting-started.md).
