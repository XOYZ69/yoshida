+++
title = "Documentation"
template = "docs-section.html"
page_template = "docs-page.html"
sort_by = "title"
+++

<img src="images/logo.png" alt="yoshida" width="320">



yoshida turns a **design** (layers, parameters and expressions in a JSON file) and a table of **card data** into finished card images. One core renders everything, and three front ends use it: a command-line tool, a visual editor that runs in the browser, and a small server.

This wiki documents version 0.4.0 of the tool and version 1 of the file format.

> Disclaimer: If you are searching for the old python version please check out [0.3.1-python](https://github.com/XOYZ69/yoshida/releases/tag/0.3.1-python)

## Start here

| I want to...                         | Read                                                       |
| ------------------------------------ | ---------------------------------------------------------- |
| Try it and render my first card      | [Getting Started](@/docs/getting-started.md)                         |
| Render from a script or CI           | [Command Line](@/docs/command-line.md)                               |
| Host the editor for myself or a team | [Server and Docker](@/docs/server-and-docker.md)                     |
| Learn how a project is laid out      | [Project Layout and Manifest](@/docs/project-layout-and-manifest.md) |
| Design a card by hand                | [Designs](@/docs/designs.md), [Params](@/docs/params.md), [Layers](@/docs/layers.md)     |
| Use the visual editor                | [Builder](@/docs/builder.md)                                         |
| Fix an error message                 | [Diagnostics](@/docs/diagnostics.md)                                 |

## The file format

- [Project Layout and Manifest](@/docs/project-layout-and-manifest.md)
- [Designs](@/docs/designs.md)
- [Params](@/docs/params.md)
- Layers: [overview](@/docs/layers.md), [rect](@/docs/layer-rect.md), [ellipse](@/docs/layer-ellipse.md), [polygon](@/docs/layer-polygon.md), [text](@/docs/layer-text.md), [image](@/docs/layer-image.md), [group](@/docs/layer-group.md), [divider](@/docs/layer-divider.md)
- [Repeat](@/docs/repeat.md), [Extends](@/docs/extends.md), [Effects](@/docs/effects.md)
- Expressions: [overview](@/docs/expressions.md), [literals and units](@/docs/expressions-literals-and-units.md), [names and references](@/docs/expressions-names-and-references.md), [operators](@/docs/expressions-operators.md), [functions](@/docs/expressions-functions.md), [templates](@/docs/expressions-templates.md), [list lookup by key](@/docs/expressions-list-lookup.md), [constants and functions](@/docs/expressions-constants-and-functions.md)
- [Card Data](@/docs/card-data.md) (JSON and CSV)
- [Rendering Model](@/docs/rendering-model.md)
- [Diagnostics](@/docs/diagnostics.md) and the list of error codes
- [Formatting and Schemas](@/docs/formatting-and-schemas.md), [Limits and Versioning](@/docs/limits-and-versioning.md)

## The tools

- [Getting Started](@/docs/getting-started.md), [Command Line](@/docs/command-line.md), [Server and Docker](@/docs/server-and-docker.md)
- The visual editor: [Builder](@/docs/builder.md), [Canvas](@/docs/builder-canvas.md), [Layers](@/docs/builder-layers.md), [Inspector](@/docs/builder-inspector.md), [Params](@/docs/builder-params.md), [Card data](@/docs/builder-card-data.md), [Files](@/docs/builder-files.md), [Problems](@/docs/builder-problems.md), [Expression editor](@/docs/builder-expression-editor.md), [Shortcuts](@/docs/builder-shortcuts.md)
- [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md)
- [Examples](@/docs/examples.md), [board game example](@/docs/example-board-game.md)

## For contributors

- [Building from Source](@/docs/building-from-source.md)
- [CI and Deployment](@/docs/ci-and-deployment.md)
- [Architecture](@/docs/architecture.md), [WASM Interface](@/docs/wasm-interface.md), [Server API](@/docs/server-api.md)
- [Known Gaps](@/docs/known-gaps.md)
- [Third-Party Notices](@/docs/third-party-notices.md)

![A card rendered from the feature-tour example](images/tour-blue.png)
