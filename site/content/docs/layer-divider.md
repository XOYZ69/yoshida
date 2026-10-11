+++
title = "Layer: divider"
+++

A divider organises the layer list in the editor. It draws nothing and takes no part in rendering.

```json
{ "id": "stats_divider", "type": "divider", "label": "Monster stats" }
```

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `id` | ident | required | Unique like every layer id (error 1108) |
| `label` | string | the id | Shown as the divider's title |
| `note` | string | | Comment |

- Any other field is error 1101.
- A divider has no bounds. It cannot be referenced with `@` (error 3002) and cannot be extended (error 1112).
- Dividers may sit at the top level or inside [groups](@/docs/layer-group.md). They do not count towards a group's bounds.

In the editor, dividers show as titled lines in the layer tree. Right-click empty space in the layer list or on the canvas and choose to add a divider. See [Builder: Layers](@/docs/builder-layers.md).

Dividers are the layer-list counterpart of the `group` field on [params](@/docs/params.md), which sorts the params list and card form into sections.
