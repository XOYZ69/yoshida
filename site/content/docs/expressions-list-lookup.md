+++
title = "Expressions: List Lookup by Key"
description = "Read list params by key instead of by position."
+++

A [list param](@/docs/params.md#lists) whose items have a `text` field can be read **by key**, not only by position.

```json
"params": {
  "stats": { "type": "list", "item": { "name": "text", "value": "number" }, "default": [] }
}
```

```json
"box": { "x": 20, "y": 40, "w": "stats.Speed * 2", "h": 12 }
"text": "Charm {stats['Charm']}"
```

## Rules

- The **key field** is the item's first `text` field. `list.Key` and `list["Key"]` (any text expression in the brackets) find the first item whose key field equals the key. The comparison is exact and case-sensitive.
- When the item has **exactly two fields** (a key and a value, such as `{ "name": "text", "value": "number" }`), the lookup gives the **value**: `stats.Speed` is a number.
- Otherwise it gives the **item**, and you read its fields: `rows.top.x`.
- After `.` a key may use upper case (`stats.Speed`). Keys with spaces or other characters use brackets: `stats["Attack power"]`.
- A list whose items have no `text` field cannot be looked up by key (error 3003).
- A key no item has is error 3104 at render time. The message lists the keys that card does have.
- Indexing by position still works: `stats[0]` is the first item.

## Lists as repeat counts

`"repeat": { "count": "stats" }` repeats once per item; it equals `len(stats)`. See [Repeat](@/docs/repeat.md).

## In the editor

The expression editor suggests the keys of the lists it can see, taken from the cards' values, as soon as you type `stats.` or `stats[`. See [Builder: Expression editor](@/docs/builder-expression-editor.md).
