#!/usr/bin/env python3
"""Card renders and landing-page images for the docs (needs Pillow and a built yoshida CLI).

    python3 web/scripts/docs-screenshots/renders.py [--bin zig-out/bin/yoshida] [--shots DIR]

Writes site/static/docs/images/poker-deck.png, board-game-road-trip.png,
forge-cards.png and cocktails-cards.png from `yoshida render` output of the
examples and their smaller copies site/static/img/examples/*.webp, and converts the landing-editor screenshots made by
`npm run docs:screenshots` (in DIR, default site/static/docs/images) to
site/static/img/editor-{light,dark}.webp when they are there.
"""
import argparse
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parents[3]
ap = argparse.ArgumentParser()
ap.add_argument("--bin", default=str(root / "zig-out/bin/yoshida"))
ap.add_argument("--shots", default=str(root / "site/static/docs/images"))
args = ap.parse_args()
images = root / "site/static/docs/images"

with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp)
    subprocess.run([args.bin, "render", str(root / "examples/poker"), "--out", str(out / "poker")], check=True)
    subprocess.run(
        [args.bin, "render", str(root / "examples/board-game"), "--out", str(out / "bg"), "--card", "road-trip"],
        check=True,
    )

    # Ten poker cards, five per row, on a transparent background.
    picks = ["numbers/AS", "numbers/7H", "numbers/10D", "numbers/8C", "courts/KS",
             "courts/QH", "courts/JD", "jokers/joker-red", "jokers/joker-black", "back/back"]
    w, h, gap = 300, 420, 16
    sheet = Image.new("RGBA", (gap + 5 * (w + gap), gap + 2 * (h + gap)), (0, 0, 0, 0))
    for i, p in enumerate(picks):
        im = Image.open(out / "poker" / f"{p}.png").convert("RGBA").resize((w, h), Image.LANCZOS)
        sheet.alpha_composite(im, (gap + (i % 5) * (w + gap), gap + (i // 5) * (h + gap)))
    sheet.save(images / "poker-deck.png", optimize=True)

    board = Image.open(out / "bg/boards/road-trip.png").convert("RGBA")
    board = board.resize((1500, round(1500 * board.height / board.width)), Image.LANCZOS)
    board.save(images / "board-game-road-trip.png", optimize=True)

    # A row of cards of one height on a transparent background.
    def row(name, files, h=560, gap=16):
        ims = []
        for f in files:
            im = Image.open(f).convert("RGBA")
            ims.append(im.resize((round(h * im.width / im.height), h), Image.LANCZOS))
        strip = Image.new("RGBA", (gap + sum(im.width + gap for im in ims), h + 2 * gap), (0, 0, 0, 0))
        x = gap
        for im in ims:
            strip.alpha_composite(im, (x, gap))
            x += im.width + gap
        strip.save(images / name, optimize=True)

    subprocess.run([args.bin, "render", str(root / "examples/forge"), "--out", str(out / "forge")], check=True)
    row("forge-cards.png", [out / "forge" / f"{p}.png" for p in
                            ["projects/foundry", "projects/reactor", "projects/market", "corporations/ironworks"]])
    # Two single cards for the feature showcase on the landing page.
    for card in ("projects/foundry", "corporations/ironworks"):
        im = Image.open(out / "forge" / f"{card}.png").convert("RGB")
        im.save(root / f"site/static/img/cards/forge-{card.split('/')[1]}.webp", quality=90, method=6)

    subprocess.run(
        [args.bin, "render", str(root / "examples/cocktails"), "--out", str(out / "cocktails"), "--date", "2026-10-11"],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    row("cocktails-cards.png", [out / "cocktails" / f"{p}.png" for p in
                                ["cocktails/001", "cocktails/012", "back/back", "menu/page1"]])

# The same four pictures, smaller, for the examples on the landing page.
(root / "site/static/img/examples").mkdir(exist_ok=True)
for name, src in [("poker", "poker-deck"), ("board-game", "board-game-road-trip"),
                  ("forge", "forge-cards"), ("cocktails", "cocktails-cards")]:
    im = Image.open(images / f"{src}.png").convert("RGBA")
    im = im.resize((960, round(960 * im.height / im.width)), Image.LANCZOS)
    im.save(root / f"site/static/img/examples/{name}.webp", quality=86, method=6)

for theme in ("light", "dark"):
    src = Path(args.shots) / f"landing-editor-{theme}.png"
    if not src.exists():
        continue  # only there after `npm run docs:screenshots`
    Image.open(src).convert("RGB").save(root / f"site/static/img/editor-{theme}.webp", quality=88, method=6)
print("done")
