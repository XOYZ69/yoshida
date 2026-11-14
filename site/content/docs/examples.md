+++
title = "Examples"
description = "The four example projects, what each one shows and how to open them."
+++

yoshida comes with four finished projects. Each is a normal project folder in [`examples/`](https://github.com/XOYZ69/yoshida/tree/master/examples), and each has a `README.md` that explains how it is built.

- **In the editor:** open the project menu (the project's name in the top bar) and pick the example. Changes are saved as your own copy.
- **On the command line:**

```sh
yoshida check examples/forge
yoshida render examples/forge --out out
```

| Example | What it is | Start here if you want |
| --- | --- | --- |
| [`forge`](#forge) | A small engine-builder card game, four cards | A card game with icons in its text. The smallest example, and the one to copy |
| [`poker`](#poker) | A full deck: 52 cards, two jokers and a back | Several designs in one project, and shapes placed by formulas |
| [`cocktails`](#cocktails) | Recipe cards, a menu and a shopping list | Lists, sums, print resolution and QR codes |
| [`board-game`](#board-game) | A printable A3 party board | One big page built from a list, ready for a print shop |

## forge

![forge, three project cards and a corporation](../images/forge-cards.png)

Three project cards and one corporation, from two designs that share a component. It is the shortest tour of the features made for card games:

- `{icon:name}` and `<b>` in card text ([text markup](@/docs/layer-text.md#bold-italic-and-icons-markup))
- SVG art and icons, sharp at any `--scale` ([image](@/docs/layer-image.md))
- a row layout for the cost coins, and a pill that fits its text ([group layout](@/docs/layer-group.md#layout-rows-and-columns))
- linear and radial gradients, with colours from params ([gradient](@/docs/layer-rect.md#gradient))
- rounded and hexagon-clipped images, and an optional image with a placeholder
- an effect panel shared by both designs as a component ([include](@/docs/layer-group.md#shared-components-include))
- a QR code with a logo ([qr](@/docs/layer-qr.md))

For a deck image per set, as tabletop simulators want it:

```sh
yoshida render examples/forge --out out --sheet 10x7
```

[`examples/forge/README.md`](https://github.com/XOYZ69/yoshida/tree/master/examples/forge) lists which card shows which feature.

## poker

![poker, a selection of cards](../images/poker-deck.png)

One project, four designs: number cards (ace to 10), court cards (J, Q, K), the joker and the back.

- `extends` for the mirrored corner indices and pips
- design functions that place the pips for every rank
- a repeated group turned 180 degrees for the double-ended court cards
- a nested repeat for the back pattern, and gold gradients
- a manifest (`yoshida.json`) that orders the four sets

How it is built, step by step: [Example: Poker Deck](@/docs/example-poker.md).

## cocktails

![cocktails, two recipe cards, the back and a menu page](../images/cocktails-cards.png)

Twenty-six recipe cards with a matching back, four menu pages and a shopping sheet at 600 dpi, all from one ingredient catalog.

- an ingredient catalog as a list param
- sums through chained hidden layers
- seven glasses drawn from one width function
- a drink colour mixed from the ingredients and drawn as a gradient
- bold alcoholic ingredients on the menu, and a QR code per card

[`examples/cocktails/README.md`](https://github.com/XOYZ69/yoshida/tree/master/examples/cocktails) explains how the sums, the mixed colour and the alcohol-free switch work.

## board-game

![board-game, road-trip board](../images/board-game-road-trip.png)

A whole board per card, built from one list param, with a theme per card.

- a 40-tile ring as one repeated group with `translate`
- design functions and an enum list field
- row and column layout, bold in the rules, a shared text size
- `canvas.dpi` and `canvas.bleed` for printing on A3

How it is built, step by step: [Example: Board Game](@/docs/example-board-game.md).

## Making your own

Copy the example closest to what you need (`forge` if in doubt), rename the design and card files, and change them in the editor. Use `yoshida check` to validate and `yoshida fmt` to keep the JSON tidy. [Getting Started](@/docs/getting-started.md) walks through a first project.

Every font in the examples is under the SIL Open Font License or a free font license and may be shared; see [Third-Party Notices](@/docs/third-party-notices.md).
