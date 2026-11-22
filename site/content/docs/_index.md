+++
title = "Documentation"
template = "docs-section.html"
page_template = "docs-page.html"
insert_anchor_links = "right"
sort_by = "title"

[extra]
headline = "Everything about yoshida"

# "Start here" cards on the docs overview. The index of all pages below
# them is generated from data/docs-nav.toml.
[[extra.start]]
want = "Make my first card"
read = ["docs/getting-started.md"]
[[extra.start]]
want = "See what yoshida can do"
read = ["docs/feature-tour.md", "docs/examples.md"]
[[extra.start]]
want = "Install it, or host it for a team"
read = ["docs/installation.md", "docs/server-and-docker.md"]
[[extra.start]]
want = "Use the visual editor"
read = ["docs/builder.md"]
[[extra.start]]
want = "Write a design by hand"
read = ["docs/designs.md", "docs/params.md", "docs/layers.md"]
[[extra.start]]
want = "Render from a script or CI"
read = ["docs/command-line.md"]
[[extra.start]]
want = "Fix an error message"
read = ["docs/diagnostics.md"]
[[extra.start]]
want = "Let an AI agent write designs"
read = ["docs/formatting-and-schemas.md"]
+++

yoshida turns a **design** (layers, parameters and expressions in a JSON file) and a table of **card data** into finished card images. One core renders everything, and three front ends use it: a command-line tool, a visual editor that runs in the browser, and a small server.

This documentation covers version 0.9.0 of the tool and version 1 of the file format.

> Looking for the old Python version? It lives on as [0.3.1-python](https://github.com/XOYZ69/yoshida/releases/tag/0.3.1-python).
