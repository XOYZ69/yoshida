+++
title = "Card Data"
+++

Card data is the table of values that fills a design's [params](@/docs/params.md), one row (JSON object or CSV line) per card. It comes in two forms.

## JSON: `*.cards.json`

```json
{
  "format": 1,
  "design": "designs/monster.design.json",
  "cards": [
    { "id": "001", "title": "Shiro of the Immanity", "level": 5, "art": "assets/images/shiro.jpg" }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `format` | `1` |
| `design` | Path of the design this file uses. Required unless the [manifest](@/docs/project-layout-and-manifest.md) lists the file in a set |
| `name` | Optional display name for the set |
| `cards` | Array of cards (at most 10000 per set, error 5001) |

Each card:

- `id` is optional text. The default is the 1-based index padded to 3 digits (`001`, `002`, ...). Ids must be unique (error 2004) and safe as file names, using only `A-Z a-z 0-9 . _ -` (error 2005). Output files are `<id>.png`.
- Every other key must be a declared param. Unknown keys are warning 2001 (with a "did you mean" hint) and are ignored.
- Values must match the param's type (error 2006). An `enum` value must be one of its options. `min`, `max` and `max_length` are enforced (error 2002). A `required` param must be present (error 2003).
- Values are **literals**. Expressions are not evaluated in card data.
- A param the card leaves out takes its `default`.

A list param holds an array of objects:

```json
{ "id": "mojito", "name": "Mojito",
  "ingredients": [ { "amount": "50", "unit": "ml", "name": "White rum" } ] }
```

or an object that changes single items of the param's default list, by position (0-based), keeping the rest:

```json
{ "id": "variant", "tiles": { "11": { "kind": "safe" } } }
```

See [Params: changing single items](@/docs/params.md#changing-single-items-of-the-default). Items are checked field by field; an [enum item field](@/docs/params.md#item-fields) with a value that is not one of its options is error 2006.

## CSV: `*.cards.csv`

```csv
id,title,author,text
00000001,Never Have I ever...,XOYZ,...got drunk.
```

- RFC 4180: comma separated, `"` for quoting, with a **header row**. Header names are `id` and param names.
- CSV cannot name its design, so the file must be listed in a set of `yoshida.json`:

```json
{ "format": 1, "name": "Simple game cards",
  "sets": [ { "name": "drinking-game", "cards": "cards/drinking-game.cards.csv", "design": "designs/gamecard.design.json" } ] }
```

- An **empty cell** means "use the default".
- `number` and `integer` cells use `.` as the decimal separator; `bool` cells are `true` or `false`; `list` cells hold a **JSON array** (or an object of changes). Colors and enums are plain text.
- A line break inside a quoted cell is a line break in the value (and in a text layer that shows it).
- A syntax problem in the file, a missing header row, or a row with a different number of fields than the header is error 1202.
- Unknown header names are warning 2001, as in JSON.

## Limits

At most 10000 cards per set. The server renders at most 1000 per request by default (`--max-cards`, see [Server and Docker](@/docs/server-and-docker.md)).

## In the editor

The **Card data** tab lists the cards with search, add, duplicate, reorder, rename and delete, for both JSON and CSV files, and shows a form built from the params below the list. **Browse** opens every card as a table or a grid of thumbnails. See [Builder: Card data](@/docs/builder-card-data.md).

Errors that belong to one card (for example 2002 or 3104) are tied to that card's id; see [Diagnostics](@/docs/diagnostics.md).
