+++
title = "Builder"
description = "The visual editor that runs in your browser, and how its panels fit together."
+++

The editor opens in **Builder** mode: a visual editor for designs and card data. Everything it does is written back to ordinary project files, so the JSON is always one click away under **Advanced (JSON)**, for anything the builder does not cover (a code editor with JSON highlighting, folding, search, bracket matching and problem markers).

<img class="only-light" src="../images/editor-params-light.png" alt="The editor with the Params tab open" width="1500" height="950">
<img class="only-dark" src="../images/editor-params-dark.png" alt="The editor with the Params tab open" width="1500" height="950">

## Screen layout

| Area | What it is | Page |
| --- | --- | --- |
| Top bar | The project menu (new, open, **New design**, **Add files**, **Save to folder**, **Export project file**, rename, saved projects, examples), whether it is saved, **Builder / Advanced (JSON)**, undo and redo, **Save** (when a folder is linked), the theme | [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md) |
| Toolbar | **Add** a layer, pick the **Design** and the **Card**, **Export** as **PNG**, **ZIP** or **PDF**, the **Export…** dialog, **Render on server** (when the server offers it) | below |
| Left panel | **Layers**, **Params**, **Card data**, **Files** tabs | [Layers](@/docs/builder-layers.md), [Params](@/docs/builder-params.md), [Card data](@/docs/builder-card-data.md), [Files](@/docs/builder-files.md) |
| Canvas | The live card with selection, move, resize, rotate | [Canvas](@/docs/builder-canvas.md) |
| Right panel | The inspector for the selected layer, or the design settings | [Inspector](@/docs/builder-inspector.md) |
| Problems panel | Every error, warning and hint, and **Check all cards** | [Problems](@/docs/builder-problems.md) |

Every panel can be resized: drag the lines between the left panel, the canvas, the right panel and the problems panel (in Advanced view: the files, editor and preview columns). Double-click a line to reset it. Sizes are remembered in the browser. Dialogs and the card browser move by their title bar and resize from the corner.

## Toolbar

- **Add a layer**: rect, ellipse, text, image or polygon. The new layer is centred and placed above the selected layer.
- **Design** picks the design being edited (with its card count and card file). **New design…** in the project menu creates a blank design with its own card file.
- **Card** picks the card shown in the preview. The arrows step through the cards; the middle opens a searchable list that stays fast with thousands of cards. At its bottom, **Browse** opens the [card browser](@/docs/builder-card-data.md#browse).
- **Export**: **PNG** exports the card you see; **ZIP** exports all cards of the set as PNG files; **PDF** exports all cards of the set as one PDF, one page per card, with crop marks when the design has a `canvas.bleed` (see [Command Line: PDF](@/docs/command-line.md#pdf)).
- **Export…** opens the [export dialog](#export-dialog) for everything else: other formats, a higher resolution, crop marks, or every design at once.
- **Render on server** appears when the editor is served by `yoshida-server` with rendering on. Switched on, **ZIP** and **PDF** are rendered by the server instead of the browser (see [Server and Docker](@/docs/server-and-docker.md#using-server-rendering-from-the-editor)). **PNG** always renders in the browser.

While an export or a check runs, a progress window covers the editor (the editor behind it is blurred): the steps, how many cards are done, the time left (from the average time per card so far; for a PDF rendered in the browser it is an estimate from the last export) and an activity log. **Cancel** stops a ZIP export, an export from the dialog, or a server render. When something fails, the window stays open with the reason until you close it.

### Export dialog

**Export…** at the end of the export buttons opens a dialog. **Enter** exports, **Escape** closes it. It remembers its settings in this browser.

<img class="only-light" src="../images/editor-export-light.png" alt="The export dialog" width="552" height="664">
<img class="only-dark" src="../images/editor-export-dark.png" alt="The export dialog" width="552" height="664">

- **What**: **This card**, **This design** (all its cards) or **All designs** (every design of the project; designs with errors are skipped and named in the dialog).
- **Formats**, one or more:
  - **PNG**: **8 bit** or **16 bit** per channel (16 bit keeps smooth gradients for print and editing; PNG has no 10 bit mode), and **Compression**: **Fast**, **Default** (what the PNG button uses) or **Smallest**. The pixels are the same at every level; only the file size and the time change.
  - **JPEG**: **Quality** 1 to 100 (default 90). JPEG has no transparency, so transparent parts are shown on the **Background** color (default white). The design's dpi is written into the file.
  - **WebP**: **Quality** 1 to 100 (default 90), or **Lossless** (true lossless in Chrome and Edge; other browsers write their highest quality). Offered when the browser can write WebP; the dialog says so when it cannot.
  - **SVG**: one vector file per card, sharp at any zoom, with text as letter outlines (see [Command Line: SVG](@/docs/command-line.md#svg)).
  - **PDF**: one page per card. **Pages**: **Vector** (the default: shapes and text stay sharp at any zoom, and the file is much smaller) or **Image** (each card as an image, like the PNG; the **PDF** button always makes these). **Crop marks**: **Auto** (when the design has a `canvas.bleed`, like the PDF button), **On** or **Off**.
- **Resolution**: **1x** (the design size) to **4x**. The dialog shows the size in pixels. The printed size does not change: PNG and JPEG files carry the dpi times the resolution, and PDF pages keep their size. SVG files and vector PDF pages use the resolution only for the parts that stay pixels (layers with a `sharpen`, `detail`, `edge_enhance` or `find_edges` [effect](@/docs/effects.md)). A resolution that would make a side of an image larger than 10000 pixels is disabled (see [Limits](@/docs/limits-and-versioning.md#limits)); vector files have no such limit.

One file (one card in one format, or one PDF) downloads as it is. Anything more is one ZIP: card images at `<design>/<card id>.<ext>` and PDFs at `<design>.pdf`, named `<project>-<design>.zip` for one design and `<project>.zip` for all designs. The line above the **Export** button says what will be written, for example "40 cards × 2 formats, 80 files in poker-numbers.zip".

JPEG and WebP are made by the browser's own image encoders, from the pixels yoshida renders. With **Render on server** on, PNG, SVG and PDF files of whole designs are rendered on the server, one request per design and format; JPEG and WebP still render in the browser (the server has no JPEG or WebP encoder, and downloading PNGs only to convert them would cost more than it saves). **This card** always renders in the browser. The dialog says what runs where.

Hovering a button or a field shows what it does in a tooltip drawn like the expression suggestions.

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
- [Fonts](@/docs/builder-fonts.md): finding, previewing and importing fonts, and their licenses
- [Params](@/docs/builder-params.md): editing params, groups, enum options
- [Card data](@/docs/builder-card-data.md): the card list, the form, the browser
- [Files](@/docs/builder-files.md): the project's files, uploads, renames
- [Problems](@/docs/builder-problems.md): the problems panel
- [Expression editor](@/docs/builder-expression-editor.md): highlighting, completion, reference
- [Shortcuts](@/docs/builder-shortcuts.md)

<img class="only-light" src="../images/editor-project-menu-light.png" alt="The project menu" width="509" height="596">
<img class="only-dark" src="../images/editor-project-menu-dark.png" alt="The project menu" width="509" height="596">
