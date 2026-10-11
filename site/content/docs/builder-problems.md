+++
title = "Builder: Problems"
+++

The **Problems** panel is the one place for every [diagnostic](@/docs/diagnostics.md): errors, warnings and hints for the design, the card files and the manifest.

## Reading it

- **Identical problems on several cards** are shown once, with the list of cards.
- Each problem is a **block colored by severity**, with:
  - the message (names set as code),
  - the fix (the hint),
  - the code (for example `3002`),
  - `file:line`,
  - where it is: `group › layer › field`.
- Toggle **errors**, **warnings** and **hints** at the top of the panel.

## Jumping

Click a block to jump to the layer, the param, the card, or (in Advanced view) the line in the code editor.

## Filtering to one layer

The [inspector](@/docs/builder-inspector.md) shows a small chip such as "● 2 errors ▲ 1 warning, show ›" in each section. Click it to filter the panel to that layer (a group includes everything inside it).

## While there are errors

The canvas keeps showing the last good picture, dimmed. Fix the errors and it refreshes.

## Preview versus final render

The preview is forgiving: a missing image is drawn as a checkered placeholder. The same project is still an error for a final render (`yoshida render`, **ZIP**), see error 4001 in [Diagnostics](@/docs/diagnostics.md).
