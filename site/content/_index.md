+++
title = "yoshida"
template = "index.html"

[extra]
kicker = "Card generator · free and open source"
headline = "One design. Every card."
lead = "Describe a card once with layers and formulas, fill it from a spreadsheet, and get a PNG for every row. Identical pixels in the browser, on the command line and on a server."
hand = ["10H", "JC", "QD", "KS", "AH"]

[[extra.steps]]
title = "Design"
text = "Shapes, text and images. Any value can be a formula that reacts to the card's data."
code = '"fill": "foil ? #F5C542 : accent"'

[[extra.steps]]
title = "Fill"
text = "Typed params, filled from a JSON or CSV file. One row per card."
code = "title,level,accent\nKuro,5,#0F8F80"

[[extra.steps]]
title = "Render"
text = "Every card to a PNG, a print PDF or a deck sheet: in the editor, from a script or on a server."
code = 'yoshida render my-game --out out'

# "Made for card games": the forge example, with the field or option that does it.
[[extra.game]]
title = "Icons and bold in card text"
text = "Write rules the way they read on the card. Icons wrap with their word."
code = "<b>Action:</b> spend 1 {icon:energy}"
link = "@/docs/layer-text.md#bold-italic-and-icons-markup"

[[extra.game]]
title = "Rows that measure themselves"
text = "Cost coins, pills and chips line up and grow with their text."
code = '"layout": { "direction": "row", "gap": 8 }'
link = "@/docs/layer-group.md#layout-rows-and-columns"

[[extra.game]]
title = "Gradients"
text = "Linear and radial, on any shape, with colours from the card's data."
code = '"gradient": { "angle": 90, "stops": ["#2B5876", "#4E4376"] }'
link = "@/docs/layer-rect.md#gradient"

[[extra.game]]
title = "SVG art, clipped and optional"
text = "Sharp at any size, with rounded corners or a polygon clip. A missing picture can show a placeholder instead of an error."
code = '"src": "{art}", "optional": true'
link = "@/docs/layer-image.md"

[[extra.game]]
title = "Shared components"
text = "One effect panel, used by every design of the game."
code = '"include": "components/effect-row.component.json"'
link = "@/docs/layer-group.md#shared-components-include"

[[extra.game]]
title = "QR codes with a logo"
text = "Link a card to its rules. yoshida warns when a code prints too small."
code = '"type": "qr", "logo_src": "{logo}"'
link = "@/docs/layer-qr.md"

[[extra.game]]
title = "Deck sheets and print files"
text = "One image per deck for tabletop simulators, or a PDF with bleed and crop marks."
code = "yoshida render my-game --sheet 10x7"
link = "@/docs/command-line.md#sheets"

[[extra.features]]
title = "Visual editor"
text = "Drag, resize and rotate layers, preview any card live. Runs in your browser; nothing is uploaded."

[[extra.features]]
title = "Formulas everywhere"
text = "Positions, colours and text from expressions, with units like 50%, vw and vh."

[[extra.features]]
title = "Smart text"
text = "Word wrap, justify, auto-shrink to fit, line limits with an ellipsis, bold, italic and inline icons."

[[extra.features]]
title = "Repeat and reuse"
text = "Draw a layer once per level star or list item; inherit with extends; share layers between designs."

[[extra.features]]
title = "Clear errors"
text = "Every problem has a code, file, line and column, often with a \"did you mean\" hint."

[[extra.features]]
title = "Plain files"
text = "A project is a folder of JSON, CSV and images. Version it with git, validate it with JSON Schema."

# The example projects. `img` is site/static/img/examples/<img>.webp
# (web/scripts/docs-screenshots/renders.py), `w` and `h` its size.
[[extra.examples]]
title = "Forge"
text = "A small engine-builder card game: icons in text, rows, gradients, SVG art, a shared component."
img = "forge"
w = 960
h = 338
link = "@/docs/examples.md#forge"

[[extra.examples]]
title = "Poker deck"
text = "52 cards, jokers and a back from four designs. Pips placed by formulas."
img = "poker"
w = 960
h = 534
link = "@/docs/example-poker.md"

[[extra.examples]]
title = "Cocktails"
text = "Recipe cards, a menu and a shopping list at 600 dpi, all from one ingredient list."
img = "cocktails"
w = 960
h = 332
link = "@/docs/examples.md#cocktails"

[[extra.examples]]
title = "Board game"
text = "A printable A3 party board: 40 tiles from one repeated group, with bleed for the print shop."
img = "board-game"
w = 960
h = 679
link = "@/docs/example-board-game.md"

[[extra.frontends]]
title = "Editor"
text = "Nothing to install. It runs in your browser and saves there; your cards are not uploaded."
code = "Project menu → Forge card game"
link = "editor/"
label = "Open the editor"

[[extra.frontends]]
title = "Command line"
text = "check, render and fmt for scripts and CI. In the release zip for Linux, macOS and Windows."
code = "yoshida check my-game\nyoshida render my-game --out out"
link = "@/docs/command-line.md"
label = "CLI reference"

[[extra.frontends]]
title = "Server"
text = "Host the editor for yourself or a team, and render big sets on the server."
code = "docker build -t yoshida .\ndocker run -p 8080:8080 yoshida"
link = "@/docs/server-and-docker.md"
label = "Server and Docker"
+++

Made for trading cards, game cards, recipe cards, flash cards and name tags: anything where one layout is filled with many sets of values.
