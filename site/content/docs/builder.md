+++
title = "Builder"
+++

The editor opens in **Builder** mode: a visual editor for designs and card data. Everything it does is written back to ordinary project files, so the JSON is always one click away under **Advanced (JSON)**, for anything the builder does not cover (a code editor with JSON highlighting, folding, search, bracket matching and problem markers).

![The editor with the Params tab open](../images/builder-v04-dark-params.png)

## Screen layout

| Area | What it is | Page |
| --- | --- | --- |
| Top bar | Project menu, **+ Design**, **Upload image**, **Add files**, **Builder / Advanced (JSON)**, undo and redo, **Save to folder**, **Export zip** | [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md) |
| Toolbar | Add a layer, pick the **Design** and the **Card**, export **PNG**, **ZIP** or **PDF**, **Check all** cards | below |
| Left panel | **Layers**, **Params**, **Card data**, **Files** tabs | [Layers](@/docs/builder-layers.md), [Params](@/docs/builder-params.md), [Card data](@/docs/builder-card-data.md), [Files](@/docs/builder-files.md) |
| Canvas | The live card with selection, move, resize, rotate | [Canvas](@/docs/builder-canvas.md) |
| Right panel | The inspector for the selected layer, or the design settings | [Inspector](@/docs/builder-inspector.md) |
| Problems panel | Every error, warning and hint | [Problems](@/docs/builder-problems.md) |

Every panel can be resized: drag the lines between the left panel, the canvas, the right panel and the problems panel (in Advanced view: the files, editor and preview columns). Double-click a line to reset it. Sizes are remembered in the browser. Dialogs and the card browser move by their title bar and resize from the corner.

## Toolbar

- **Add a layer**: rect, ellipse, text, image or polygon. The new layer is centred and placed above the selected layer.
- **Design** picks the design being edited (with its card count and card file). **+ Design** in the top bar creates a blank design with its own card file.
- **Card** picks the card shown in the preview. The arrows step through the cards; the middle opens a searchable list that stays fast with thousands of cards. At its bottom, **Browse** opens the [card browser](@/docs/builder-card-data.md#browse).
- **PNG** exports the card you see; **ZIP** exports all cards of the set as PNG files; **PDF** exports all cards of the set as one PDF, one page per card, with crop marks when the design has a `canvas.bleed` (see [Command Line: PDF](@/docs/command-line.md#pdf)).
- **Check all** evaluates every card of the set without drawing it and shows what it finds in the [Problems panel](@/docs/builder-problems.md): errors that only some cards have, such as too many layers or a missing image.

## How edits are written

- The builder changes the parsed design and writes it back with the [canonical formatter](@/docs/formatting-and-schemas.md), so the JSON view always matches.
- Every property field takes a literal or an [expression](@/docs/expressions.md). Number labels can be dragged sideways to scrub the value. The `value` / `expr` switch turns colors and booleans into an expression. The `param` menu binds a field to a param of the right type (`accent`, or `{title}` in text). Colors use a built-in picker (saturation/value square, hue, alpha, hex).
- All dialogs, menus and dropdowns are drawn by the editor in its own light or dark theme; there are no browser `prompt` / `confirm` boxes or native `<select>` lists.
- Canvas moves and resizes keep how a value is written: `120` stays a number, `50%` stays a percentage, `@panel.bounds.top + 60` becomes `@panel.bounds.top + 70`, and any other expression gets `+ 10` appended (in parentheses when needed). Resizing moves the anchor point by the right amount for the layer's `anchor`.
- Fields a layer inherits through [`extends`](@/docs/extends.md) are marked with ↳; editing one adds an override to this layer.
- Renaming a layer updates every `@id` reference and `extends`. Renaming a param updates every layer field and every card file of the design, in one undo step.
- While the design has errors, the last good picture stays on the canvas, dimmed, and the problems show next to the fields they belong to.
- Undo and redo cover builder, card form and text edits. A drag, a scrub or a run of nudges is one step, and a param rename across several files is one step too.

## Pages

- [Canvas](@/docs/builder-canvas.md): selecting, moving, resizing, rotating, snapping, zoom and pan
- [Layers](@/docs/builder-layers.md): the layer tree, groups, dividers, the layer menu
- [Inspector](@/docs/builder-inspector.md): fields, align and distribute, design settings
- [Params](@/docs/builder-params.md): editing params, groups, enum options
- [Card data](@/docs/builder-card-data.md): the card list, the form, the browser
- [Files](@/docs/builder-files.md): the project's files, uploads, renames
- [Problems](@/docs/builder-problems.md): the problems panel
- [Expression editor](@/docs/builder-expression-editor.md): highlighting, completion, reference
- [Shortcuts](@/docs/builder-shortcuts.md)

![The project menu](../images/v03-project-menu.png)
