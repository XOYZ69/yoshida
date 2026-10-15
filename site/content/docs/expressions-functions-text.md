+++
title = "Expressions: Text"
description = "Search, cut, pad, repeat and reshape text, counting characters."
+++

Positions and lengths in these functions count **characters** (Unicode code points), not bytes, so `slice('Æble', 0, 1)` is `Æ`. A text result longer than 10 000 bytes is error 3106.

Text can come from a text param, a card value, a [template](@/docs/expressions-templates.md) or a string literal.

## Searching

### `contains(text, part)`

`(text, text) -> bool`. True when `part` occurs in `text`. The comparison is exact (case-sensitive).

- `contains('Fire Dragon', 'Dragon')` is `true`.
- An empty `part` is always `true`.

### `starts_with(text, prefix)`

`(text, text) -> bool`. True when `text` begins with `prefix`.

- `starts_with('Fire Dragon', 'Fire')` is `true`.
- An empty `prefix` is always `true`.

### `ends_with(text, suffix)`

`(text, text) -> bool`. True when `text` ends with `suffix`.

- `ends_with('Fire Dragon', 'gon')` is `true`.
- An empty `suffix` is always `true`.

Example: a rule that only applies to some card types:

```json
"visible": "starts_with(card_type, 'Spell')"
```

## Changing text

### `replace(text, old, new)`

`(text, text, text) -> text`. Replaces every occurrence of `old` with `new`.

- `replace('a-b-c', '-', ' ')` is `a b c`.
- An empty `old` leaves `text` unchanged.
- A result over 10 000 bytes is error 3106.

### `repeat(text, n)`

`(text, number) -> text`. `text` repeated `n` times. `n` is floored; `n` of zero or less gives an empty text.

- `repeat('★', 3)` is `★★★`.
- A result over 10 000 bytes is error 3106.

Example: a rating of 5 stars, with the empty stars drawn in another colour:

```json
"text": "{repeat('★', rating)}{repeat('☆', 5 - rating)}"
```

### `pad_start(text, width[, fill])`

`(text, number[, text]) -> text`. Pads `text` on the left with the first character of `fill` until it is `width` characters long. `width` is floored. When `fill` is left out, a space is used.

- `pad_start('7', 3, '0')` is `007`.
- `pad_start('12', 4)` is `  12`.
- An empty `fill`, or a `text` already `width` characters or longer, gives `text` unchanged.
- A result over 10 000 bytes is error 3106.

Example: card numbers such as `007`. `pad_start` takes text, so the number is first made text with `fmt`:

```json
"text": "{pad_start(fmt(render.index + 1, 0), 3, '0')}"
```

### `slice(text, start[, end])`

`(text, number[, number]) -> text`. The characters from index `start` up to, but not including, `end`. Indices are floored and start at 0. A negative index counts from the end. Indices outside the text are clamped to it. When `end` is left out, the text runs to its end. If `end` is not after `start`, the result is empty.

- `slice('Fire Dragon', 0, 4)` is `Fire`.
- `slice('Fire Dragon', -6)` is `Dragon`.
- `slice('Fire Dragon', 5, 2)` is empty.

Example: the initials of a name, for a small badge:

```json
"text": "{slice(name, 0, 1)}"
```

### `title_case(text)`

`(text) -> text`. Upper-cases the first letter of each word and leaves the other letters as they are. Words are separated by white space and by `-`. The case mapping is the one used by `upper`.

- `title_case('fire-breathing dragon')` is `Fire-Breathing Dragon`.

### `roman(n)`

`(number) -> text`. The Roman numeral for `n`, in upper case. `n` is floored and must be from 1 to 3999.

- `roman(2026)` is `MMXXVI`.
- `roman(4)` is `IV`.
- A number outside 1 to 3999 is error 3107.

Example: a chapter heading:

```json
"text": "Chapter {roman(chapter)}"
```

### `part(text, sep, n)`

`(text, text, number) -> text`. Splits `text` at every `sep` and gives piece `n`. Pieces are counted from 0. `n` is floored; a negative `n` counts from the last piece. A piece that does not exist gives an empty text.

- `part('Fire/Water', '/', 0)` is `Fire`.
- `part('Fire/Water', '/', -1)` is `Water`.
- `part('Fire', '/', 3)` is empty.
- An empty `sep` is error 3107.

Example: the second word of a type line such as `Creature/Beast`:

```json
"text": "{part(card_type, '/', 1)}"
```
