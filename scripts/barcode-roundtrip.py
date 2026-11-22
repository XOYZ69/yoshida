#!/usr/bin/env python3
"""Renders every barcode format and reads the result back with ZXing.

For each case it builds a one-layer design, renders PNG, SVG and a vector PDF
with the built yoshida binary, decodes all three with zxing-cpp and compares
text and format. Needs `pip install zxing-cpp pillow` and, for SVG and PDF,
rsvg-convert and pdftoppm (poppler). Run from the repository root after
`zig build`:

    python3 scripts/barcode-roundtrip.py [--bin zig-out/bin/yoshida] [--only code128,ean13]
"""
import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

import zxingcpp
from PIL import Image

# format, text given to the layer, text ZXing should read, ZXing format name,
# extra layer fields
CASES = [
    ("qr", "https://example.com/yoshida?card=42", None, "QRCode", {}),
    ("qr", "HELLO WORLD 12345", None, "QRCode", {"level": "high"}),
    ("qr", "31415926535897932384626433832795028841971693993751", None, "QRCode", {"mode": "numeric", "level": "low"}),
    ("qr", "HTTPS://EXAMPLE.COM/ABC-123 $5.00", None, "QRCode", {"mode": "alphanumeric"}),
    ("qr", "Order 4711: https://example.com/o/12345678901234567890 – danke ÄÖÜ", None, "QRCode", {"mode": "auto"}),
    ("qr", "plain bytes with ümlauts", None, "QRCode", {"mode": "byte"}),
    ("code128", "Yoshida-42/abc", None, "Code128", {"label": True}),
    ("code128", "1234567890", None, "Code128", {}),
    ("code128", "ABC123456789xyz", None, "Code128", {"label": True, "align": "left"}),
    ("code128", "SPREAD", None, "Code128", {"label": True, "align": "justify"}),
    ("ean13", "400638133393", "4006381333931", "EAN13", {}),
    ("ean13", "4006381333931", None, "EAN13", {"label": False}),
    ("ean13", "9780201379624", None, "EAN13", {"label": True}),
    ("ean8", "9638507", "96385074", "EAN8", {}),
    ("upca", "03600029145", "0036000291452", "UPCA", {}),
    ("code39", "YOSHIDA-42", None, "Code39", {"label": True}),
    ("code39", "CARD 7", "CARD 7L", "Code39", {"check": "add"}),
    ("itf", "1234567890", None, "ITF", {"label": True}),
    ("itf", "12345", "012345", "ITF", {}),
    ("itf14", "1234567890123", "12345678901231", "ITF", {}),
    ("codabar", "A12345B", None, "Codabar", {}),
    ("codabar", "98765", "A98765B", "Codabar", {}),
    ("code93", "YOSHIDA93", None, "Code93", {"label": True}),
    ("datamatrix", "Yoshida Data Matrix 12345", None, "DataMatrix", {}),
    ("datamatrix", "1234567890123456", None, "DataMatrix", {}),
    ("aztec", "Yoshida Aztec 12345", None, "Aztec", {}),
    ("aztec", "Yoshida Aztec 12345 with more error correction", None, "Aztec", {"ecc": 60}),
    ("pdf417", "Yoshida PDF417 12345 and more text to fill a row", None, "PDF417", {}),
    ("pdf417", "12345678901234567890123456789012345678901234567890", None, "PDF417", {}),
    ("pdf417", "Mixed: lower, UPPER, 123, punct;<>@[]_ and ümlauts ✓", None, "PDF417", {"ecc": 4}),
]

# ZXing reports these names; ITF-14 reads as ITF.


# Texts that fill every symbol size of the 2D formats, so that every region
# layout, placement corner case and block interleave is read back.
SWEEPS = {
    # Data Matrix: data codewords of each size, as digit pairs
    "datamatrix": [("datamatrix", ("7081" * 2000)[: 2 * n], None, "DataMatrix", {})
                   for n in (3, 5, 8, 12, 18, 22, 30, 36, 44, 62, 86, 114, 144, 174, 204, 280, 368, 456, 576, 696, 816, 1050, 1304, 1558)],
}


def mixed(n, seed=1):
    """n characters of letters, digits, punctuation and spaces, repeatable."""
    import random

    rnd = random.Random(seed)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:;!?-_/+=()[]#%&*@"
    return "".join(rnd.choice(alphabet) for _ in range(n))


SWEEPS["aztec"] = (
    [("aztec", mixed(n, n), None, "Aztec", {}) for n in (3, 12, 25, 40, 60, 90, 130, 190, 260, 350, 450, 560, 700, 850, 1000, 1200, 1500, 1650)]
    + [("aztec", "".join(str(i % 10) for i in range(n)), None, "Aztec", {}) for n in (20, 300, 1500, 3000)]
    + [("aztec", "ÄÖÜ grüße — ✓ " * 5, None, "Aztec", {}), ("aztec", "A" * 400, None, "Aztec", {})]
)


SWEEPS["pdf417"] = (
    [("pdf417", mixed(n, n), None, "PDF417", {}) for n in (1, 10, 40, 100, 250, 500, 800, 1000)]
    + [("pdf417", mixed(120, 7), None, "PDF417", {"ecc": e}) for e in range(0, 9)]
    + [("pdf417", "".join(str(i % 10) for i in range(n)), None, "PDF417", {}) for n in (13, 44, 45, 300, 1200)]
    + [("pdf417", "Zeilen\r\nund\tTabs, ÄÖÜß € ✓" * 6, None, "PDF417", {})]
)


def design(cases, size=(640, 320)):
    return {
        "format": 1,
        "name": "Barcode round trip",
        "canvas": {"width": size[0], "height": size[1], "background": "#FFFFFF"},
        "params": {
            "fmt": {"type": "text", "default": "code128"},
            "v": {"type": "text", "default": "x"},
            "lab": {"type": "bool", "default": True},
            "al": {"type": "text", "default": "center"},
            "chk": {"type": "text", "default": "auto"},
            "lvl": {"type": "text", "default": "medium"},
            "md": {"type": "text", "default": "auto"},
            "ec": {"type": "number", "default": -1},
        },
        "layers": [
            {
                "id": "code",
                "type": "barcode",
                "format": "fmt",
                "text": "{v}",
                "label": "lab",
                "align": "al",
                "check": "chk",
                "level": "lvl",
                "mode": "md",
                "ecc": "ec",
                "box": {"x": 10, "y": 10, "w": size[0] - 20, "h": size[1] - 20},
            }
        ],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", default="zig-out/bin/yoshida")
    ap.add_argument("--only", default="")
    ap.add_argument("--keep", default="")
    ap.add_argument("--sweep", default="", help="comma list of formats to run through every symbol size")
    args = ap.parse_args()
    only = set(filter(None, args.only.split(",")))
    cases = [c for c in CASES if not only or c[0] in only]
    size = (640, 320)
    if args.sweep:
        cases = [c for f in args.sweep.split(",") for c in SWEEPS[f]]
        size = (1400, 1400)
    exe = str(pathlib.Path(args.bin).resolve())
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="barcode-rt-"))
    (tmp / "designs").mkdir()
    (tmp / "cards").mkdir()
    (tmp / "yoshida.json").write_text(
        json.dumps({"format": 1, "name": "rt", "sets": [{"name": "s", "design": "designs/d.design.json", "cards": "cards/c.cards.json"}]})
    )
    (tmp / "designs" / "d.design.json").write_text(json.dumps(design(cases, size)))
    cards = []
    for i, (fmt, text, _exp, _zx, extra) in enumerate(cases):
        card = {"id": f"c{i:02d}", "fmt": fmt, "v": text}
        if "label" in extra:
            card["lab"] = extra["label"]
        if "align" in extra:
            card["al"] = extra["align"]
        if "check" in extra:
            card["chk"] = extra["check"]
        if "level" in extra:
            card["lvl"] = extra["level"]
        if "mode" in extra:
            card["md"] = extra["mode"]
        if "ecc" in extra:
            card["ec"] = extra["ecc"]
        cards.append(card)
    (tmp / "cards" / "c.cards.json").write_text(json.dumps({"format": 1, "design": "designs/d.design.json", "cards": cards}))

    def run(*a):
        r = subprocess.run([exe, *a], capture_output=True, text=True)
        if r.returncode != 0:
            sys.stdout.write(r.stdout + r.stderr)
            raise SystemExit(f"yoshida {' '.join(a)} failed")
        return r

    run("check", str(tmp))
    out = tmp / "out"
    run("render", str(tmp), "--out", str(out))
    run("render", str(tmp), "--out", str(out / "svg"), "--svg")
    run("render", str(tmp), "--out", str(out / "pdf"), "--pdf", "--vector")

    pages = {}
    if shutil.which("pdftoppm"):
        subprocess.run(["pdftoppm", "-r", "150", "-png", str(out / "pdf" / "s.pdf"), str(out / "pdf" / "page")], check=True)
        pages = {i: sorted((out / "pdf").glob("page-*.png"))[i] for i in range(len(cases))}

    failed = 0
    for i, (fmt, text, exp, zx, extra) in enumerate(cases):
        want = exp if exp is not None else text
        imgs = {"png": out / "s" / f"c{i:02d}.png"}
        svg = out / "svg" / "s" / f"c{i:02d}.svg"
        if shutil.which("rsvg-convert") and svg.exists():
            png = out / "svg" / f"c{i:02d}.svg.png"
            subprocess.run(["rsvg-convert", "-z", "2", "-b", "white", "-o", str(png), str(svg)], check=True)
            imgs["svg"] = png
        if i in pages:
            imgs["pdf"] = pages[i]
        for kind, path in imgs.items():
            # UPC-A is the bars of an EAN-13 with a leading 0; ZXing only calls
            # it UPC-A when asked for that format.
            kw = {"formats": zxingcpp.BarcodeFormat.UPCA} if zx == "UPCA" else {}
            res = zxingcpp.read_barcodes(Image.open(path).convert("L"), **kw)
            ok = len(res) == 1 and res[0].text == want and res[0].format.name == zx
            tag = "ok  " if ok else "FAIL"
            got = [(r.format.name, r.text) for r in res]
            print(f"{tag} {fmt:10} {kind:3} {len(text)}c {text[:12]!r} -> {got if not ok else want!r:.60}")
            if not ok:
                failed += 1
    if args.keep:
        shutil.copytree(out, args.keep, dirs_exist_ok=True)
    shutil.rmtree(tmp, ignore_errors=True)
    if failed:
        raise SystemExit(f"{failed} decode(s) failed")
    print("all decoded")


if __name__ == "__main__":
    main()
