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
text = "Every card to a PNG, in the editor, from a script or on a server."
code = 'yoshida render tour --out out'

[[extra.features]]
title = "Visual editor"
text = "Drag, resize and rotate layers, preview any card live. Runs in your browser; nothing is uploaded."

[[extra.features]]
title = "Smart text"
text = "Word wrap, justify, auto-shrink to fit, line limits with an ellipsis."

[[extra.features]]
title = "Formulas everywhere"
text = "Positions, colours and text from expressions, with units like 50%, vw and vh."

[[extra.features]]
title = "Repeat and reuse"
text = "Draw a layer once per level star or list item; inherit from another layer with extends."

[[extra.features]]
title = "Clear errors"
text = "Every problem has a code, file, line and column, often with a \"did you mean\" hint."

[[extra.features]]
title = "Plain files"
text = "A project is a folder of JSON, CSV and images. Version it with git, validate it with JSON Schema."

[[extra.frontends]]
title = "Editor"
text = "WebAssembly in your browser. Autosaves locally."
link = "editor/"
label = "Open the editor"

[[extra.frontends]]
title = "Command line"
text = "check, render and fmt for scripts and CI."
link = "@/docs/command-line.md"
label = "CLI reference"

[[extra.frontends]]
title = "Server"
text = "Renders whole sets over HTTP and returns a zip. Docker image included."
link = "@/docs/server-and-docker.md"
label = "Server and Docker"
+++

Made for trading cards, game cards, recipe cards, flash cards and name tags: anything where one layout is filled with many sets of values.
