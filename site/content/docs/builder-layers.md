+++
title = "Builder: Layers"
description = "The layer tree: reorder, group, hide and lock layers."
+++

The **Layers** tab lists the design's layers **topmost first**, as a tree.

## The tree

- **Groups** fold open and closed (▸ / ▾) and show how many layers they hold.
- **Dividers** (`"type": "divider"`) show as titled lines that organise the list and are never drawn. See [Layer: divider](@/docs/layer-divider.md).
- The **eye** sets `visible`. The **lock** stops canvas clicks (editor only).
- **Badges** show the group size, repeat, extends, effects and problems. A group shows the worst problem inside it.

## Selecting and reordering

- <kbd>Ctrl</kbd>+click and <kbd>Shift</kbd>+click select several layers.
- **Drag rows** to reorder, or drop onto the **middle of a group row** to move layers into that group.
- <kbd>Ctrl</kbd>+<kbd>Up</kbd> / <kbd>Down</kbd> moves the selected layer in the stack (see [Shortcuts](@/docs/builder-shortcuts.md)).

## Adding

- The toolbar adds a rect, ellipse, text, image or polygon, centred and above the selected layer.
- **Right-click on empty space** (in the list or on the canvas) to add a layer, an empty group or a divider.

## Layer menu

Right-click a layer or use the ⋯ button:

| Item | Does |
| --- | --- |
| Rename | Renames the layer and updates every `@id` reference and `extends` |
| Duplicate | Copies the layer (new id with a suffix) |
| Copy / Cut / Paste | Through the system clipboard, see below |
| Group / Ungroup | Wraps the selected layers in a group, or dissolves a group |
| Bring forward / Send backward | Moves one step in the stack |
| Move out of the group | Takes a layer out of its group |
| Show / Hide | Toggles `visible` |
| Lock / Unlock | Editor-only lock |
| Delete | Removes the layer; asks first when other layers refer to it |

## Groups

<kbd>Ctrl</kbd>+<kbd>G</kbd> groups the selected layers: the group goes where the topmost of them was, and keeps their order. <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>G</kbd> ungroups. Moving a group moves every layer in it. See [Layer: group](@/docs/layer-group.md).

## Copy, cut and paste

<kbd>Ctrl</kbd>+<kbd>C</kbd>, <kbd>Ctrl</kbd>+<kbd>X</kbd> and <kbd>Ctrl</kbd>+<kbd>V</kbd> work on the selected layers through the **system clipboard**, so layers move between designs, projects and even browser tabs. Pasted ids get `_copy` added, and `@` references among the pasted layers follow the new ids.

<img class="only-light" src="../images/editor-layers-group-light.png" alt="Layers in a group" width="1500" height="950">
<img class="only-dark" src="../images/editor-layers-group-dark.png" alt="Layers in a group" width="1500" height="950">
