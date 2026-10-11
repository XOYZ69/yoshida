+++
title = "Formatting and Schemas"
+++

## Canonical formatting (`yoshida fmt`)

Every tool writes JSON the same way, so files never churn between the CLI, the editor and the server.

- 2 spaces indent, LF line endings, trailing newline.
- One property per line, except that an object containing only scalars, or an array containing only scalars or only arrays of scalars (such as `[x, y]` points), stays on one line when the whole line fits in 100 columns. The line length counts the indent, the `"key": ` prefix and the value, in UTF-16 code units. So `box`, `at`, `stroke` and most params sit on one line, while layers spread out.
- **Key order is kept exactly as written**; the formatter never reorders keys. The editor writes `id` and `type` first in new layers and keeps the order of existing ones.

```sh
yoshida fmt my-cards            # rewrite the project's JSON files
yoshida fmt my-cards --check    # list files that would change; exit status 1 if any
```

You can also pass a single file. See [Command Line](@/docs/command-line.md#yoshida-fmt). CI runs `fmt --check` on the examples, see [CI and Deployment](@/docs/ci-and-deployment.md).

In the editor, the builder changes the parsed design and writes it back with the same formatter, so the JSON view always matches. See [Builder](@/docs/builder.md).

## Comments

JSON has no comments. Use the `note` field (every layer, the design, the manifest and params accept one) for comments.

## JSON Schemas

Schemas for editors live in `schema/` of the repository (JSON Schema draft 2020-12):

| File | For |
| --- | --- |
| `schema/design.schema.json` | `*.design.json` |
| `schema/cards.schema.json` | `*.cards.json` |
| `schema/yoshida.schema.json` | `yoshida.json` |

Add a `$schema` key at the top of a file (adjust the relative path):

```json
{
  "$schema": "../../schema/design.schema.json",
  "format": 1,
  "name": "My design"
}
```

or map the file patterns to the schemas in your editor's settings (in VS Code, `json.schemas`). The core ignores the `$schema` key.

The schemas give autocompletion and structural checks. They cannot check expressions, references between layers or card values against params; `yoshida check` does that.
