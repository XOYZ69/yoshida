+++
title = "Expressions: Lists"
description = "Find, total, count and join the items of a list param."
+++

These functions read a list, such as a [list param](@/docs/params.md#lists) or the list that `repeat` counts. None of them builds a new list: lists come only from list params. Items are read by key or by field, as described on [List lookup by key](@/docs/expressions-list-lookup.md).

## The field argument

Several functions take an optional `'field'` argument, which names a field of the list's items.

- The field is a **text literal** in quotes, such as `'Speed'`. A variable or an expression is not allowed. The name is checked when the design loads, so a misspelt field is reported then, not while a card renders.
- **Without the argument**, the field is the list's **value field**: the item's only field, or, for a key/value list (an item with exactly two fields, a text key and a value), the field that is not the key. When neither applies, the function is error 3003, asking for the field.
- The **key field** is the item's first `text` field. `has`, `get` and `index_of` compare keys with it, and it is the same key that `list.Key` uses. A list whose items have no `text` field is error 3003 for these functions.

## Finding items

### `has(list, key)`

`(list, text) -> bool`. True when an item has the key `key`.

- `has(stats, 'Speed')` is `true` on a card whose `stats` list has a `Speed` item.

Use it to guard a lookup that might fail (error 3104):

```json
"text": "{has(stats, 'Speed') ? stats.Speed : 0}"
```

### `get(list, key, fallback)`

`(list, text, value) -> value`. The value of the item with that key, or `fallback` when no item has it. For a key/value list, the value has the value's type and `fallback` must have that type too.

### `get(list, key, 'field', fallback)`

`(list, text, 'field', value) -> field type`. The same, for any list with a key field: it reads the named field of the item with that key. `fallback` must have the field's type.

- `get(stats, 'Speed', 0)` is the Speed value, or `0` when the card has no Speed item.
- `get(rows, 'top', 'x', 0)` is the `x` field of the `top` item, or `0`.

### `index_of(list, key)`

`(list, text) -> number`. The position (from 0) of the first item with that key, or `-1` when no item has it. Pairs with `list[n]`.

- `index_of(stats, 'Speed')` is `1` when Speed is the second item.
- `index_of(stats, 'Luck')` is `-1` when there is no Luck item.

## Totals and averages

### `sum(list[, 'field'])`

`(list[, 'field']) -> number`. The total of a number field. The field must be a number field. An empty list gives `0`.

- `sum(stats)` is the total of the values of a key/value list of numbers.

### `avg(list[, 'field'])`

`(list[, 'field']) -> number`. The average of a number field. An empty list is error 3103.

### `min(list[, 'field'])`, `max(list[, 'field'])`

`(list[, 'field']) -> number`. The smallest or largest value of a number field. An empty list is error 3103.

When the first argument is a list, `min` and `max` take this form. With numbers as arguments they are the functions on [Functions](@/docs/expressions-functions.md#existing-functions).

- `max(scores, 'points')` is the highest `points` value.

## Counting and joining

### `count(list, 'field', value)`

`(list, 'field', value) -> number`. The number of items whose field equals `value`. The value must have the field's type. To count every item, use `len(list)`.

- `count(spells, 'school', 'fire')` is the number of spells of the fire school.

### `join(list[, 'field'], sep)`

`(list[, 'field'], text) -> text`. The values of a field, joined with `sep` between them. Each value is printed as in a [template](@/docs/expressions-templates.md): a number with at most 12 significant digits, trailing zeros removed, `true` or `false` for a bool, text as it is, and a color as `#RRGGBBAA`. An empty list gives an empty text. A result over 10 000 bytes is error 3106.

- `join(tags, ', ')` is `Fire, Flying` for a list of two tags with those values.

### `last(list)`

`(list) -> item`. The last item, the same as `list[len(list) - 1]`. Read its fields as with `list[n]`. An empty list is error 3102.

- `last(levels).name` is the name of the final level.
