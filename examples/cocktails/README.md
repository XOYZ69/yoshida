# Cocktail cards

Party cocktail cards, a menu and a shopping list, all at 600 dpi: twenty-six recipes and a matching back (63 x 88 mm with 3 mm bleed, 1632 x 2220 px, the trim line is 70 px inside the edge), A4 menu pages and an A4 shopping sheet.

```sh
yoshida check examples/cocktails
yoshida render examples/cocktails --out out
yoshida render examples/cocktails --out out --set cocktails --pdf --crop-marks   # print sheets
```

| Set | Design | Cards |
| --- | --- | --- |
| `cocktails` | `designs/cocktail.design.json` | Twenty-six recipes, ids `001` ... `026` |
| `back` | `designs/back.design.json` | `back` |
| `menu` | `designs/menu.design.json` | Four pages with up to eight drinks each |
| `shopping` | `designs/shopping.design.json` | `party`: what to buy for the chosen drinks |

What it shows:

- **An ingredient catalog**: the `catalog` param lists every ingredient once, with its English name, color, alcohol in % vol, unit, tint, an alcohol-free alternative and the bottle size. A card picks an ingredient from a dropdown (`ingredients[].ingredient` is an enum) and only adds the `amount` and `unit`. `vol` on a card item overrides the alcohol for that card (`-1` keeps the catalog's value). A new ingredient is one new catalog row plus its name in the options of the `ingredient` field.
- **Alcohol-free versions**: `virgin` swaps every alcoholic ingredient for its alternative from the catalog (`alt`), so a virgin card is the same recipe with one switch.
- **Drink color**: `liquid_mode: auto` mixes the ingredient colors by volume and tint, through a chain of hidden layers whose `fill` carries the running mix. `custom` uses `liquid`.
- **Groups and extends**: the card is built from groups (`face`, `stage` with the `glass` inside, `corners`, `badges`, `recipe`). The glass group has its own origin (`translate`), each ingredient row is one repeated group, and hidden base layers hold what several layers share.
- **Sums without a fixed number of slots**: a repeated hidden layer chains boxes as wide as each ingredient, so the end of the last box is the total. The cards use it for volume and % vol, the shopping list for the amount per ingredient (rows sorted by ingredient, a box starts where the previous one of the same ingredient ends). Read the values through `@layer.bounds`, from a group that is not moved sideways: a translated group changes the `x` it reads.
- **Glasses**: highball, tumbler, martini, hurricane, shot, coupe and wine glass. The outline and the drink are polygons whose points come from one width function, `hw`.
- **Design functions**: `tr` picks the German or English label (`lang`), `dec`, `num` and `pct` print numbers, `ing_name`, `ing_color`, `ing_vol` read the catalog.
- **QR code**: the `url` param becomes a `qr` layer (dots, rounded corner squares). Leave `url` empty to hide it. The layer warns (3208) when a module would print narrower than 0.5 mm: that depends on the printed size of the code and the length of the link, not on the resolution, so short links are the fix.
- **Menu**: `menu.cards.json` is generated from the card data (names, % vol, mixed color); the ingredient names come from the same catalog.
- **Shopping list**: the `party` param picks drinks (dropdown) and glasses per drink; the sheet adds a reserve and rounds up to bottles.

The alcohol shown is the undiluted mix in % vol: the pure alcohol of the ingredients divided by the total volume of the ingredients in `cl` or `ml`. Other units (teaspoons, pieces, dashes) do not count towards the volume.

Fonts: Pacifico and Poppins, both under the SIL Open Font License (see `assets/fonts/*-license.txt`).
