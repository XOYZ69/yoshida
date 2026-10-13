+++
title = "Builder: Expression Editor"
description = "Suggestions, signatures, hover info, formatting and the formula panel for expression fields."
+++

Expression and template fields in the inspector are small code editors for [expressions](@/docs/expressions.md) and [templates](@/docs/expressions-templates.md).

<img class="only-light" src="../images/editor-expr-suggest-light.png" alt="Suggestions while typing" width="1500" height="950">
<img class="only-dark" src="../images/editor-expr-suggest-dark.png" alt="Suggestions while typing" width="1500" height="950">

## Highlighting

Numbers and units, strings, colors (with a swatch), `@layer` references and their fields, params, repeat names, built-ins, functions, keywords and operators each get their own color. **Unknown names are underlined.** In templates the `{…}` holes are tinted.

The editor uses the same parser as the core, so what it marks is exactly what loading the design reports. Every broken spot gets a red mark, not only the first one.

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

<img class="only-light" src="../images/editor-expr-signature-light.png" alt="Signature help" width="1500" height="950">
<img class="only-dark" src="../images/editor-expr-signature-dark.png" alt="Signature help" width="1500" height="950">

## The ƒ reference

The **ƒ** button in a field opens a reference of everything available there: repeat names, params, layers, built-ins, functions, units, operators and template syntax. Clicking an entry inserts it.

<img class="only-light" src="../images/editor-expr-reference-light.png" alt="The ƒ reference" width="1500" height="950">
<img class="only-dark" src="../images/editor-expr-reference-dark.png" alt="The ƒ reference" width="1500" height="950">

## Long expressions

- Long text wraps inside the field, and <kbd>Shift</kbd>+<kbd>Enter</kbd> starts a new line.
- <kbd>Shift</kbd>+<kbd>Alt</kbd>+<kbd>F</kbd> (or <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F</kbd>) **reformats** the expression: one `?:` branch or `match` pair per line, redundant parentheses removed, numbers and colors kept as written. It is a normal edit, so undo brings the old text back.
- Under the text, a **breadcrumb** shows where the caret is, such as `match › arg 4 › with_alpha › arg 1`.

## The formula panel

The **⤢** button in a field (or <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>E</kbd>) opens the field in a panel at the right edge of the window. The outline on the left lists the calls and conditions of the expression; the main area shows the selected part by its shape:

- a `match(...)` as a table of key and result rows, with **+ row** and a delete button per row,
- a chain of `?:` conditions as *when → then* rows and an *else* row,
- a single `?:` as *when*, *then* and *else*,
- an `in [...]` test as chips you can add and remove,
- anything else as one text box.

Colors show a swatch. The whole expression stays editable as text at the bottom, and both views follow each other. A cell that does not parse keeps what you typed and turns red; the expression changes only once it parses. Edits from the panel rewrite the expression in its canonical layout.

**Live values.** For the card shown on the stage, every part shows its value, and the row of a `match` or `?:` chain that was taken is marked. Values come from a real render of the card, so repeat names, function arguments and `@layer` positions are the actual ones. A field that the card never evaluates (a hidden layer, an unused constant) says so.

**Quick actions.**

- *Convert to match* turns a `?:` chain that tests one value (`k == 'a' ? … : k == 'b' ? … : …`, also with `k in [...]`) into a `match`, and *Convert to ?: chain* turns it back.
- *Extract constant* moves the selected part into a new design constant and puts its name in its place. It is offered for parts that use no repeat names, function arguments or layer references.
- *Extract function* moves it into a new design function whose arguments are the repeat names and arguments it uses, and puts the call in its place.

**Apply** (or <kbd>Ctrl</kbd>+<kbd>Enter</kbd> in the text) writes the expression to the field. Closing the panel applies pending changes too.

## Committing

A field is committed on <kbd>Enter</kbd> (<kbd>Ctrl</kbd>+<kbd>Enter</kbd> in multi-line fields) or when it loses focus. <kbd>Esc</kbd> reverts.

## Related

[Literals and units](@/docs/expressions-literals-and-units.md), [Names and references](@/docs/expressions-names-and-references.md), [Functions](@/docs/expressions-functions.md)
