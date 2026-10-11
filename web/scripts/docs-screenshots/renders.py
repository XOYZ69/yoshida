#!/usr/bin/env python3
"""Card renders and landing-page images for the docs (needs Pillow and a built yoshida CLI).

    python3 web/scripts/docs-screenshots/renders.py [--bin zig-out/bin/yoshida] [--shots DIR]

Writes site/static/docs/images/poker-deck.png and board-game-road-trip.png from
`yoshida render` output of the two examples, and converts the landing-editor
screenshots made by `npm run docs:screenshots` (in DIR, default
site/static/docs/images) to site/static/img/editor-{light,dark}.webp.
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

for theme in ("light", "dark"):
    src = Path(args.shots) / f"landing-editor-{theme}.png"
    Image.open(src).convert("RGB").save(root / f"site/static/img/editor-{theme}.webp", quality=88, method=6)
print("done")
