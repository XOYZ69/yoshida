+++
title = "Limits and Versioning"
description = "Size limits, how to raise them and how the format is versioned."
+++

## Limits

| What                                            | Limit                               | Can be raised with | Error    |
| ----------------------------------------------- | ----------------------------------- | ------------------ | -------- |
| Visible layers drawn per card, after `repeat` expansion (checked per card) | 500      | `YOSHIDA_MAX_LAYERS` | 5001   |
| Iterations of one `repeat`                      | 1000                                | `YOSHIDA_MAX_REPEAT` | 5001   |
| Canvas                                          | 10000 x 10000 pixels                | `YOSHIDA_MAX_CANVAS` | 5001   |
| Rendered image at an export resolution (canvas x resolution) | 10000 pixels per side  | `YOSHIDA_MAX_CANVAS` | 5001   |
| Image size                                      | 50 megapixels                       | `YOSHIDA_MAX_IMAGE_MP` | 4002 |
| Cards per set                                   | 10000                               | `YOSHIDA_MAX_SET_CARDS` | 5001 |
| Group nesting                                   | 16 levels                           | fixed              | 5001     |
| Nesting inside one expression                   | 200 levels                          | fixed              | 3001     |
| Text made by a function                         | 10000 bytes                         | fixed              | 3106     |
| Sheet (`yoshida render --sheet`)                | 20000 pixels per side, 400 megapixels | fixed            | CLI error |
| Server: cards per render request                | 1000 by default (`--max-cards`)     | `YOSHIDA_MAX_CARDS` | HTTP 413 |
| Server: request body                            | 200 MB by default (`--max-body-mb`) | `YOSHIDA_MAX_BODY_MB` | HTTP 413 |

Only **visible** layers count toward the layer limit: every visible repeat iteration is one layer, hidden layers and hidden iterations are free, and a visible group counts as one plus its visible layers. The limit depends on card data, so it is evaluated per card: `yoshida check` (and **Check all** in the editor) evaluates every card and reports the cards over it, naming the layers that use most of the budget. When rendering such a card, the layers up to the limit are drawn, the PNG is written and marked as written with errors, and the run exits with status 1. See [Repeat](@/docs/repeat.md#the-layer-limit).

Exports at a higher resolution (the editor's [export dialog](@/docs/builder.md#export-dialog), `yoshida render --scale`, the server's `"scale"`) render the canvas that many times larger, and the rendered image must stay within the canvas limit too: with the default, a 4961 x 3508 canvas can be exported at 2x (9922 x 7016) but not at 3x. A card over it is not drawn and gets error 5001; the export dialog disables those resolutions. SVG files and vector PDFs are not bound by it: they use the resolution only for the parts that stay pixels, which are drawn at a lower resolution when the area is very large.

### Raising a limit

The defaults suit cards and keep a mistake (a `repeat` over the wrong list, a canvas in the wrong unit) from using all memory. A project that needs more can raise them with environment variables. Each takes a whole number of 1 or more, or the word `unlimited`; leaving it unset or empty keeps the default. Anything else is refused when the program starts, with a message that names the variable.

| Variable | Default | Counts | `unlimited` means |
| --- | --- | --- | --- |
| `YOSHIDA_MAX_LAYERS` | 500 | Visible layers drawn per card | No limit |
| `YOSHIDA_MAX_REPEAT` | 1000 | Iterations of one `repeat` | No limit |
| `YOSHIDA_MAX_CANVAS` | 10000 | Pixels per side of the canvas and of an exported image | 65535 pixels per side |
| `YOSHIDA_MAX_IMAGE_MP` | 50 | Megapixels of one image file | No limit |
| `YOSHIDA_MAX_SET_CARDS` | 10000 | Cards in one set | No limit |

```sh
YOSHIDA_MAX_LAYERS=2000 yoshida check my-game
YOSHIDA_MAX_LAYERS=unlimited YOSHIDA_MAX_REPEAT=5000 yoshida render my-game
```

Who reads them:

- **The command line** (`yoshida check` and `yoshida render`), from the environment it is started in.
- **The server**, from its environment or, with Docker Compose, from `.env` ([Server and Docker](@/docs/server-and-docker.md#docker-compose)). It prints the limits that differ from the defaults when it starts and lists them all in [`/api/capabilities`](@/docs/server-api.md).
- **The editor** has no environment. Served by a yoshida server, it takes that server's limits when it starts, so the editor and **Render on server** accept the same designs. Opened from plain files or from the project's website, it keeps the defaults.

A variable can also lower a limit, for a shared server.

**What a higher limit costs.** Every layer is drawn, so render time grows with the number of layers; a card with 5000 layers takes about ten times as long as one with 500. A bitmap needs 8 bytes per pixel while it is drawn: 800 MB for 10000 x 10000, 3.2 GB for 20000 x 20000. An image file needs 4 bytes per pixel once decoded. With `unlimited` nothing stops a design from asking for more memory than the machine has; the render then fails with an out-of-memory error. The editor runs in the browser, which gives one page at most 4 GB: a bitmap of more than about 268 megapixels (16384 x 16384) is refused there with error 5001 whatever the limit says. Projects that rely on raised limits only work where the limits are raised, so note them in the project's `README`.

**What stays fixed.** Group nesting (16) and nesting inside an expression (200) guard the program's own stack, so removing them could crash it. The length of text made by a function and the sheet size are not configurable yet.

The server's `--max-cards` and `--max-body-mb` are limits of one request, separate from the limits of a design.

## Versioning

`format` is an integer in every JSON file. These docs describe **format 1**, implemented by yoshida **0.9.0**.

- Adding optional fields with defaults does not bump the version. Fields added within format 1 so far: `canvas.dpi`, `canvas.bleed`, `consts`, `functions`, group `repeat` and `translate`, text `stroke` and `shrink_group`, stroke `dash` and `arrow`, ellipse `arc`, polygon `shape`, enum list item fields and item field defaults, list changes by position in card data, `@layer[n]` references. Older yoshida versions report the new fields as unknown (error 1101).
- A new major format version comes with a migration in the core. A file with a `format` the tool does not know is error 1105.
- The format version is printed by `yoshida version`.
- A planned `yoshida migrate` command (rewrite files in place and keep everything else byte-identical) is **not implemented yet**: version 1 is the only version, so there is nothing to migrate.

Ideas that are not in format 1 (rich text, shared design parts via `include`, per-card layer overrides) are listed in [Known Gaps](@/docs/known-gaps.md).
