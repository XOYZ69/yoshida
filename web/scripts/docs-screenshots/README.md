# Documentation screenshots

Retakes every editor screenshot used by the docs, in light and dark, from the current editor.

```sh
cd web
npm run build                    # the shots run against web/dist
npm run docs:screenshots         # writes site/static/docs/images/<name>-light.png and -dark.png
python3 scripts/docs-screenshots/renders.py   # card renders (needs Pillow and zig-out/bin/yoshida) and the landing webp images
```

Options for `npm run docs:screenshots` (after `--`): `--only name,name`, `--section overview|layers|card-data|expressions`, `--theme light|dark`, `--build`, `--base URL` (use a running editor), `--out DIR`.

- One file per section in `shots/`. A shot names the docs page it belongs to, an alt text, and a `run(h)` that sets up the UI state. Helpers are in `lib.mjs`.
- Every shot starts in a fresh browser context at 1500 x 950 (nothing saved), with the Poker deck example open, and the theme set the same way the site's switch does.
- The repository README shows `editor-params` (light and dark) too.
- Docs pages show both images: `<img class="only-light" ...>` followed by `<img class="only-dark" ...>`.
- `manifest.json` (written by a full run) lists each image, its docs page and alt text.
- The shots use only the two bundled examples, so they stay the same until the editor's UI changes.
