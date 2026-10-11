+++
title = "Limits and Versioning"
+++

## Limits

| What                                            | Limit                               | Error    |
| ----------------------------------------------- | ----------------------------------- | -------- |
| Canvas                                          | 10000 x 10000 pixels                | 5001     |
| Visible layers drawn per card, after `repeat` expansion (checked per card) | 500 | 5001 |
| Iterations of one `repeat`                      | 1000                                | 5001     |
| Group nesting                                   | 16 levels                           | 5001     |
| Image size                                      | 50 megapixels                       | 4002     |
| Cards per set                                   | 10000                               | 5001     |
| Server: cards per render request                | 1000 by default (`--max-cards`)     | HTTP 413 |
| Server: request body                            | 200 MB by default (`--max-body-mb`) | HTTP 413 |

Only **visible** layers count toward the 500-layer limit: every visible repeat iteration is one layer, hidden layers and hidden iterations are free, and a visible group counts as one plus its visible layers. The limit depends on card data, so it is evaluated per card: `yoshida check` (and **Check all** in the editor) evaluates every card and reports the cards over it, naming the layers that use most of the budget. When rendering such a card, the layers up to the limit are drawn, the PNG is written and marked as written with errors, and the run exits with status 1. See [Repeat](@/docs/repeat.md#the-layer-limit).

The server can lower the card and body limits, not raise the core limits. See [Server and Docker](@/docs/server-and-docker.md).

## Versioning

`format` is an integer in every JSON file. This wiki documents **format 1**, implemented by yoshida **0.5.0**.

- Adding optional fields with defaults does not bump the version. Fields added within format 1 so far: `canvas.dpi`, `canvas.bleed`, `consts`, `functions`, group `repeat` and `translate`, text `stroke` and `shrink_group`, stroke `dash` and `arrow`, ellipse `arc`, polygon `shape`, enum list item fields and item field defaults, list changes by position in card data, `@layer[n]` references. Older yoshida versions report the new fields as unknown (error 1101).
- A new major format version comes with a migration in the core. A file with a `format` the tool does not know is error 1105.
- The format version is printed by `yoshida version`.
- A planned `yoshida migrate` command (rewrite files in place and keep everything else byte-identical) is **not implemented yet**: version 1 is the only version, so there is nothing to migrate.

Ideas that are not in format 1 (rich text, shared design parts via `include`, per-card layer overrides) are listed in [Known Gaps](@/docs/known-gaps.md).
