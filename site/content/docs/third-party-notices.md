+++
title = "Third-Party Notices"
description = "Licences of the fonts and libraries yoshida ships with."
+++

> This page is the authoritative list. Every release bundle carries a copy as `THIRD_PARTY.md`.

## Components

| Component | Used for | License |
| --- | --- | --- |
| stb_image, stb_truetype (Sean Barrett) | PNG, JPEG, GIF and BMP decoding; font rendering | Public domain or MIT |
| simplewebp (Miku AuahDark) | WebP decoding | BSD-3-Clause (notice in `src/c/simplewebp.h`) |
| Lato (Łukasz Dziedzic) | Bundled default font | SIL Open Font License 1.1 (`src/core/assets/OFL.txt`) |
| Noto Sans Symbols 2 (The Noto Project Authors), subset | Bundled fallback font for arrows, shapes, stars and other symbols | SIL Open Font License 1.1 (`src/core/assets/NotoSansSymbols2-OFL.txt`) |
| Svelte | Web editor UI | MIT |
| CodeMirror 6, Lezer | Code editor in the Advanced view and the expression fields | MIT |
| fflate | Zip files in the browser | MIT |

The JavaScript packages are bundled into `web/assets/*.js` by Vite. Their full license texts are in `web/node_modules/<package>/LICENSE` after `npm install`.

## Example fonts

Copied from the old Python version of yoshida (`data/fonts/`) so the examples render as designed. They are not part of yoshida itself.

| Font | Example | License |
| --- | --- | --- |
| Bebas Regular (Dharma Type) | gamecard-simple | Free font EULA, `examples/gamecard-simple/assets/fonts/Bebas-Regular-license.txt` |
| Secret Code (Matthew Welch) | gamecard-simple | MIT-style, `examples/gamecard-simple/assets/fonts/secrcode-license.txt` |
| Yu-Gi-Oh! Matrix Book, Matrix Regular Small Caps 2, ITC Stone Serif Small Caps Bold, Stone Serif Semibold | yugioh, cocktail | Commercial fonts; no license to redistribute |
| yumin (Yu Mincho) | yugioh | Commercial font bundled with Windows; no license to redistribute |

**Because of the commercial fonts, a bundle that contains them is for private use only.** Remove `examples/*/assets/fonts/` (except gamecard-simple) before sharing it; the designs then fall back to Lato with warning 4005.

The GitHub Pages build does this automatically: `npm run examples -- --public` skips the files listed in `examples/.public-exclude`. See [CI and Deployment](@/docs/ci-and-deployment.md).

## Your own fonts and images

yoshida does not check licenses. If you add fonts or images to a project, make sure you may use them and, before you share a project or export, that you may redistribute them.
