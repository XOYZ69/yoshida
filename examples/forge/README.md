# Forge card game

A small card game in the style of an engine builder: three project cards and one corporation. It is the shortest example that uses icons in text, row layout, gradients, clipped and optional images, a shared component and a QR code with a logo. The art, icons and logo are simple SVG files in `assets/`.

```sh
yoshida check examples/forge
yoshida render examples/forge --out out
yoshida render examples/forge --out out --sheet 10x7   # one deck image per set, e.g. for Tabletop Simulator
yoshida render examples/forge --out out --svg
```

What it shows:

- **Icons and bold in text** (`"markup": true`): card data such as `"<b>Action:</b> spend 1 {icon:energy} to gain 2 {icon:steel}"`. The icons come from `"icons": "assets/icons/*.svg"` in each design.
- **SVG images**: art, icons and the logo are SVG files, drawn sharp at any `--scale`.
- **Row layout** (`"layout"` on a group): the cost coins line up from the right edge of the header, and the requirement pill measures its text and icon. The pill behind it reads `@req_row.bounds`.
- **Expressions for enum fields**: `req_side` moves the requirement between centred and right-aligned (`"align": "req_side == 'right' ? 'end' : 'center'"`).
- **Gradients**: the header (linear, colors from params), the empty art placeholder (radial) and the corporation band (a polygon).
- **Clipped images**: the art has rounded corners (`"radius"`), the corporation logo is clipped to a hexagon (`"clip"`).
- **Optional images**: Night Market names an art file that does not exist; with `"optional": true` the art is hidden instead of being an error, and a placeholder shows instead.
- **Shared components**: both designs take the effect panel from `components/effect-row.component.json` with `"include"`.
- **QR code with a logo**: the corporation links to its rules with the logo in the middle (`"logo_src": "{logo}"`).
