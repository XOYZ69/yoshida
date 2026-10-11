# yoshida website

Landing page, documentation (the former GitHub wiki) and release notes, built with [Zola](https://www.getzola.org/) 0.23.6. The deploy workflow (`.github/workflows/deploy.yml`) builds this site, builds the web editor into `/editor/` and publishes both to GitHub Pages.

```sh
cd site
zola serve          # http://127.0.0.1:1111, rebuilds on save
zola build          # fails on any broken internal link or anchor
```

- Docs are `content/docs/*.md`, one file per page, each with a `description` in its front matter (shown on the overview cards and as the meta description). The sidebar, the overview index and the previous/next links all come from `data/docs-nav.toml`. Link between pages with `[text](@/docs/page.md#anchor)`.
- Page content goes through Zola's template engine: wrap lines containing `{{`, `{%` or `{#` in `{% raw %}...{% endraw %}`.
- Search runs in the browser (`static/docs.js`) over an index that Zola renders with `templates/search-data.html` to `/search-data/`: one entry per page and per h2/h3 section. No server or build step beyond `zola build` is needed, so it works on GitHub Pages and in the Docker image alike.
- Release pages are generated in CI from GitHub Releases (`scripts/releases-to-zola.py`); only `content/releases/_index.md` is committed. Locally the list is empty unless you run the script yourself.
- Colours: `sass/site.scss` holds the Paper palette as `light-dark()` pairs. The editor uses the same palette in `web/src/app.css`; keep the two in sync. Both store the visitor's theme choice in `localStorage["yoshida.theme"]`, so it carries over between site and editor.
- Fonts in `static/fonts/` are self-hosted Google Fonts (Inter, JetBrains Mono, Fraunces; SIL Open Font License, latin subset).
- Hero cards in `static/img/cards/` are renders of `examples/poker` (500 x 700 WebP, named by card id); the editor screenshots in `static/img/` are taken from the built editor with the poker example open.
