+++
title = "Getting Started"
description = "Three ways to use yoshida, and your first rendered card."
+++

There are three ways to use yoshida. They all produce the same pixels.

| Way | Best for |
| --- | --- |
| The editor in your browser | Designing cards visually, previewing, exporting PNGs or a zip |
| The `yoshida` command-line tool | Scripts, CI, batch rendering |
| `yoshida-server` / Docker | Hosting the editor, rendering big sets on a server |

## Option 1: the release zip (nothing to install)

Download and unzip a release. It contains prebuilt binaries for Linux (x86_64 and aarch64), macOS (Intel and Apple Silicon) and Windows (x86_64), plus the editor, the examples and the JSON Schemas.

| System | Start the editor |
| --- | --- |
| Linux | `./start.sh` |
| macOS | double-click `start.command`, or run `./start.sh` in Terminal |
| Windows | double-click `start.bat` |

Open <http://localhost:8080/editor/> (the start scripts on macOS and Windows open it for you; the docs are at `/docs/`). For another port run `./start.sh 9000` (or `start.bat 9000`). The start scripts listen on `127.0.0.1` only, so only your own computer can reach the editor. To share it, see [Server and Docker](@/docs/server-and-docker.md).

macOS binaries are unsigned. `start.sh` clears the quarantine flag; if Gatekeeper still asks, right-click the file and choose Open once.

## Option 2: Docker

```sh
docker build -t yoshida .
docker run -p 8080:8080 yoshida
```

Then open <http://localhost:8080/editor/> (the landing page is at `/`, the docs at `/docs/`). Details: [Server and Docker](@/docs/server-and-docker.md).

## Option 3: the hosted editor

If the repository publishes to GitHub Pages, the editor is available at `https://<user>.github.io/<repo>/`. Everything runs in your browser; see [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md) and [CI and Deployment](@/docs/ci-and-deployment.md).

## Your first card in the editor

1. Open the editor and choose the project menu (the project's name in the top bar). Pick **Poker deck** from the examples.
2. Click layers on the canvas or in the **Layers** tab and change values in the inspector on the right.
3. Switch to **Card data** to edit the cards, or use the **Card** picker in the toolbar to switch cards.
4. Use **PNG** to export the card you see, or **ZIP** for every card.
5. **Export project file** (project menu) downloads the whole project as a `.yoshida` file, which you can open again later or, unzipped, render with the command line.

More in [Builder](@/docs/builder.md).

## Your first card on the command line

```sh
# check a project for problems
bin/x86_64-linux/yoshida check examples/poker

# render every card to PNG
bin/x86_64-linux/yoshida render examples/poker --out out
```

Use the binary folder that matches your system: `x86_64-linux`, `aarch64-linux`, `x86_64-macos`, `aarch64-macos` or `x86_64-windows` (`yoshida.exe`). The output goes to `out/<set>/<card id>.png`. All options: [Command Line](@/docs/command-line.md).

## Your first project from scratch

A project is a folder. The smallest useful one has a design and no card data (it then renders one card with all defaults):

```txt
hello/
  designs/hello.design.json
```

```json
{
  "format": 1,
  "name": "Hello",
  "canvas": { "width": 600, "height": 400, "background": "#1E1E28" },
  "params": {
    "title": { "type": "text", "default": "Hello" }
  },
  "layers": [
    {
      "id": "headline",
      "type": "text",
      "text": "{title}",
      "at": { "x": "50%", "y": "50%" },
      "anchor": "center",
      "size": 72,
      "color": "#FFFFFF"
    }
  ]
}
```

```sh
yoshida render hello
```

To make several cards, add card data, for example `cards/hello.cards.json`:

```json
{
  "format": 1,
  "design": "designs/hello.design.json",
  "cards": [
    { "id": "en", "title": "Hello" },
    { "id": "ja", "title": "こんにちは" }
  ]
}
```

(The default font is Lato, which has no Japanese glyphs. Declare a font that has them under `fonts`; see [Designs](@/docs/designs.md) and warning 4003 in [Diagnostics](@/docs/diagnostics.md).)

## Where to go next

- The format, from the top: [Project Layout and Manifest](@/docs/project-layout-and-manifest.md), [Designs](@/docs/designs.md), [Params](@/docs/params.md), [Layers](@/docs/layers.md).
- Working examples: [Examples](@/docs/examples.md).
- Something went wrong: [Diagnostics](@/docs/diagnostics.md).
