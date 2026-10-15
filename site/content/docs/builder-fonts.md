+++
title = "Builder: Fonts"
description = "Find, preview, import and assign fonts, with their licenses."
+++

The **Fonts** window finds fonts, previews them, imports them into the project and sets them on a text layer. It has two sources:

- **In project**: the font files already in the project.
- **Google Fonts**: a list of free fonts. It is off until you allow it.

## Opening the window

- The **Aa** button next to a text layer's `font` field.
- **Browse fonts…** at the bottom of the `font` dropdown, and in the Fonts section of the design settings.
- **Fonts…** in the project menu.

The title shows how many fonts match the search, for example "Fonts (12 of 1,935)". The search field has focus when the window opens. Arrow keys move through the list, <kbd>Enter</kbd> uses the selected font and <kbd>Esc</kbd> closes the window.

## Preview text and size

The preview text starts as the text of the selected text layer. With no text layer selected, it is the family name. You can type any text.

The **Size** buttons set the preview to S (15 px), M (28 px) or L (48 px). Every row uses the same text and size, so families are easy to compare.

## In project

The list shows each font file in the project, with the font names that point to it in this design. The detail shows:

- the file path,
- the family, style, copyright and license strings from the font's `name` table,
- the layers that use it,
- the license status.

Each font shows at most one warning, with at most one action:

- **No license file.** Add a license file next to the font, or use the action to save the license text from the font's name table.
- **License limits sharing.** The license forbids redistribution or limits use to personal use, as some free font EULAs do. Check the license before you share the project.
- **Restricted embedding.** The font's embedding bits restrict use. Check the font's terms first.
- **Variable font.** Only the default style is drawn. See [Variable fonts](#variable-fonts).
- **Not a TrueType or OpenType file.** The font cannot be drawn. See [Uploading a font file](#uploading-a-font-file).

The button at the bottom right is **Use on layer** when a text layer is selected, and **Add to design** otherwise.

## Uploading a font file

Click **Upload font file…** in the window or in the Inspector. The editor reads the file header before it copies the file into the project.

- `.ttf`, `.otf` and `.ttc` files are accepted. A `.ttc` collection draws only its first face.
- `.woff`, `.woff2` and `.eot` files are refused. They are compressed web formats, and the renderer reads only TrueType (`.ttf`) and CFF (`.otf`) files. The editor shows this reason. Use the desktop font file from the publisher instead.

## Google Fonts

The Google Fonts source lists about 1,900 families with their category, designer and license.

### Consent

Until you allow it, nothing is fetched. The first time you open the tab, a card asks **Use Google Fonts?** and says what is contacted. Choose **Allow Google Fonts** or **Not now**. The choice is remembered in this browser.

Once allowed, the browser contacts:

- `fonts.googleapis.com` and `fonts.gstatic.com`, for previews and font files,
- `raw.githubusercontent.com`, for license texts.

Google receives your IP address and the preview text. Project files are not sent. The list of families ships with the editor, so opening the tab does not contact Google.

To turn Google Fonts off, use **Turn off** in the footer of the window. Nothing is fetched again until you allow it.

### Offline

If Google cannot be reached, the window says *Google Fonts can't be reached. Project fonts still work.* **Try again** retries the request. Fonts in the project work offline.

## Importing a font

1. Choose a family and tick the styles you want, for example Regular and Bold.
2. Read the license in the detail. Check the font names. Each style gets one name, such as `playfair_display_bold`. The name is filled in for you and you can change it. It must be a valid name and not already in use.
3. Click **Import and use** when a text layer is selected, or **Import** otherwise.

Each style is saved as a file in `assets/fonts/`, named `<Family>-<Style>.ttf`. For example, Playfair Display Bold becomes `assets/fonts/PlayfairDisplay-Bold.ttf`. Its license is saved next to it as `PlayfairDisplay-Bold-license.txt`. Each style is declared in the design under its font name. If a text layer is selected, that layer switches to the first style you chose.

The whole import is one undo step. If the license cannot be downloaded, nothing is imported.

## Licenses

The license panel shows the license name, the designer and a one-line summary. The full text opens in an expander, and the panel says where the license file is saved.

The summary is a plain reading of the license, to help you choose. It is not legal advice. Read the full text when it matters.

## Variable fonts

A variable font, such as `Inter[wght].ttf`, holds many weights in one file. yoshida draws only its default style, so you cannot pick Bold from it. That is why the Google Fonts source imports static files, one file per style. For your own fonts, use static files too, one per weight.

## Fonts are declared per design

Each design lists the fonts it uses in its `fonts` (see [Designs](@/docs/designs.md#fonts)). A design that uses `extends` does not inherit the fonts of the design it extends. Import a font into each design that needs it.

## Refreshing the Google Fonts list

The list is stored in `web/public/fonts/google-fonts.json`. The editor loads it only when the Google Fonts source is opened. It is built by `scripts/font-catalog.mjs` from Google's font metadata. To refresh it, run this from the repository root:

```sh
node scripts/font-catalog.mjs
```

## Related

[Inspector](@/docs/builder-inspector.md), [Layer: text](@/docs/layer-text.md), [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md#fonts-and-licenses)
