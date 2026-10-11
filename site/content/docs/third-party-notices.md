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

Used by the projects in `examples/`. They are not part of yoshida itself, and all of them may be redistributed with the examples.

| Font | Example | License |
| --- | --- | --- |
| DM Serif Display (Colophon Foundry, based on Source Serif by Adobe) | poker | SIL Open Font License 1.1, `examples/poker/assets/fonts/DMSerifDisplay-Regular-license.txt` |
| Cinzel Decorative Bold (Natanael Gama) | poker | SIL Open Font License 1.1, `examples/poker/assets/fonts/CinzelDecorative-Bold-license.txt` |
| Bebas Regular (Dharma Type) | board-game | Free font EULA (commercial and non-commercial use, no sale), `examples/board-game/assets/fonts/Bebas-Regular-license.txt` |

The suit symbols on the poker cards come from the bundled Noto Sans Symbols 2 subset listed above.

The GitHub Pages build copies the examples with `npm run examples -- --public`, which skips the files listed in `examples/.public-exclude` (empty for now). See [CI and Deployment](@/docs/ci-and-deployment.md).

## Your own fonts and images

yoshida does not check licenses. If you add fonts or images to a project, make sure you may use them and, before you share a project or export, that you may redistribute them.
