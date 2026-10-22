+++
title = "Builder: Files"
description = "The project's files as a folder tree: add, rename, move and delete."
+++

The **Files** tab shows the project's files as a folder tree.

<img class="only-light" src="../images/editor-files-light.png" alt="The Files tab" width="1500" height="950">
<img class="only-dark" src="../images/editor-files-dark.png" alt="The Files tab" width="1500" height="950">

## What it shows

- A **coloured icon per kind of file**: designs, card data, other JSON (such as `yoshida.json`), fonts, Markdown, PDF, text and license files, and images. Images show a small **thumbnail** instead when the browser can draw it.
- File sizes in one column on the right, and folder sizes, which add up the files inside. Hover a folder's size for its file count.
- How many files refer to a file (for example `3↩`), only when at least one does. Hover the count for the list.
- Folders. **Clicking a folder** makes it the place uploads go (the upload button and **Add files** in the project menu use it; without a choice, the upload button adds to the project root and **Add files** sorts by type, so images go to `assets/images/`). The line above the tree says where uploads go, and the folder is marked in the tree. The **×** button on that line goes back to the project root. Clicking a file does not change the folder.
- Clicking a file shows its details below the tree: the pixel size of an image, the family and style of a font, what a JSON file is (a design and its name, card data and the number of cards, or the project manifest), the size, and which files use it.
- Only the tree scrolls: the search field stays at the top, and the file total and the selected file's details stay at the bottom.

## Actions

Right-click for: open, rename, duplicate, upload here, new folder, delete (which tells you what uses the file).

- **Drag files onto a folder** to move them, or **drop files from your computer** onto a folder.
- Dropping files on the window outside the tree sorts them by type: images go to `assets/images/`, fonts to `assets/fonts/`, `*.design.json` to `designs/`, `*.cards.*` to `cards/`, and a single dropped `.yoshida` project file (or a `.zip` from an older export) opens as a project.
- Empty folders are kept with a hidden `.keep` file.

## Renames rewrite references

Renaming or moving a file rewrites every reference to it in designs and card data (JSON and CSV), in **one undo step**. Path templates such as `attribute-{attribute}.png` cannot be rewritten; the editor lists them first so you can fix them by hand.

## Advanced view

The Advanced (JSON) view uses the same tree next to the code editor. See [Builder](@/docs/builder.md).

## Related

[Saving, Images and Privacy](@/docs/saving-images-and-privacy.md), [Layer: image](@/docs/layer-image.md)
