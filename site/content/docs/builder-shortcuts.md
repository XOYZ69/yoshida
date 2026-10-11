+++
title = "Builder: Shortcuts"
description = "Keyboard shortcuts for the editor."
+++

On macOS use <kbd>Cmd</kbd> where the table says <kbd>Ctrl</kbd>. Shortcuts that edit layers work in Builder mode when the focus is not in a text field.

| Keys | Does |
| --- | --- |
| <kbd>Ctrl</kbd>+<kbd>Z</kbd> | Undo |
| <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd> or <kbd>Ctrl</kbd>+<kbd>Y</kbd> | Redo |
| <kbd>Ctrl</kbd>+<kbd>C</kbd> / <kbd>X</kbd> / <kbd>V</kbd> | Copy, cut, paste layers (system clipboard) |
| <kbd>Ctrl</kbd>+<kbd>A</kbd> | Select all unlocked top-level layers |
| <kbd>Ctrl</kbd>+<kbd>D</kbd> | Duplicate the selection |
| <kbd>Ctrl</kbd>+<kbd>G</kbd> | Group the selection |
| <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>G</kbd> | Ungroup |
| <kbd>Delete</kbd> / <kbd>Backspace</kbd> | Delete the selection |
| Arrow keys | Nudge by 1 px (<kbd>Shift</kbd>: 10 px) |
| <kbd>Ctrl</kbd>+<kbd>Up</kbd> / <kbd>Down</kbd> | Move the layer in the stack (one layer selected) |
| <kbd>Esc</kbd> | Deselect (or close the card browser) |

## Mouse

| Action | Does |
| --- | --- |
| Click | Select (inside a group: the group; double-click: the layer) |
| <kbd>Shift</kbd>/<kbd>Ctrl</kbd>/<kbd>Cmd</kbd>+click | Add or remove from the selection |
| Drag on empty space | Select by rectangle |
| <kbd>Alt</kbd>+click | Pick the layer underneath |
| Hold <kbd>Ctrl</kbd> while dragging | Move without snapping |
| <kbd>Shift</kbd> while rotating | 15° steps |
| <kbd>Ctrl</kbd>+wheel or pinch | Zoom toward the pointer |
| Middle mouse button drag | Move the view (also over layers) |
| Wheel / <kbd>Shift</kbd>+wheel | Move the view up and down / sideways (when not fitted) |
| Right-click | Layer menu, or add menu on empty space |
| Drag a number label sideways | Scrub the value |

In expression fields: <kbd>Ctrl</kbd>+<kbd>Space</kbd> opens suggestions, <kbd>Enter</kbd> / <kbd>Tab</kbd> inserts, <kbd>Esc</kbd> closes or reverts. See [Expression editor](@/docs/builder-expression-editor.md).

A drag, a scrub or a run of nudges is **one** undo step; so is a param rename across several files.
