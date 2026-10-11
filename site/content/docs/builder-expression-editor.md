+++
title = "Builder: Expression Editor"
+++

Expression and template fields in the inspector are small code editors for [expressions](@/docs/expressions.md) and [templates](@/docs/expressions-templates.md).

![Suggestions while typing](../images/v03-expr-suggest.png)

## Highlighting

Numbers and units, strings, colors (with a swatch), `@layer` references and their fields, params, repeat names, built-ins, functions, keywords and operators each get their own color. **Unknown names are underlined.** In templates the `{…}` holes are tinted.

## Suggestions

As you type, the editor suggests, grouped and typed:

- repeat names and item fields,
- params, with their type, label and note,
- `@layer` ids and then their fields (`@panel.` lists `bounds.left` ... `bounds.cy`),
- `canvas.`, `card.`, `render.`,
- the keys of list params, such as `stats.Speed`, taken from the cards' values,
- functions, with signature, description and example,
- keywords.

Suggestions that do not fit the field (a color in a number field) are ranked lower and say why.

- <kbd>Ctrl</kbd>+<kbd>Space</kbd> shows everything.
- <kbd>Enter</kbd> or <kbd>Tab</kbd> inserts.
- <kbd>Esc</kbd> closes the list, or reverts the field.

## Signature help

Inside a function call a tooltip shows the signature with the current argument highlighted.

![Signature help](../images/v03-expr-signature.png)

## The ƒ reference

The **ƒ** button in a field opens a reference of everything available there: repeat names, params, layers, built-ins, functions, units, operators and template syntax. Clicking an entry inserts it.

![The ƒ reference](../images/v03-expr-reference.png)

## Committing

A field is committed on <kbd>Enter</kbd> (<kbd>Ctrl</kbd>+<kbd>Enter</kbd> in multi-line fields) or when it loses focus. <kbd>Esc</kbd> reverts.

## Related

[Literals and units](@/docs/expressions-literals-and-units.md), [Names and references](@/docs/expressions-names-and-references.md), [Functions](@/docs/expressions-functions.md)
