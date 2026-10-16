<p align="center">
  <img src="logo.png" alt="yoshida" width="360">
</p>
<p align="center">
  <strong>Design, Create, Export - Your cards, your data*</strong>
</p>
<p align="center">
	*There is a toggle to render cards server-side which is <b>OPTIONAL</b> but this will cause your data to leave your local machine.
</p>

> If you are looking for the old version (the cursed origin of this) please checkout [0.3.1-python](https://github.com/XOYZ69/yoshida/releases/tag/0.3.1-python)

yoshida is the card creator I always wanted. Way too complicated, way too many possibilties... and now with a functional Browser version.
Design your cards and just apply the data, press export and happy playing, printing, whatever you wanna do.

Designs are simple json files that are easy to share, modify and abuse as much as you want.

<p align="center">
  <img src="samples/builder-v04-dark-params.png" alt="The yoshida editor" width="100%">
</p>

> The full documentation lives on the [docs site](https://yoshida.xoyz.dev/docs/).

## Features

- Fully functional **Browser based Editor**
- **Layers** to create any shape, text or effect you need (if something is missing open an issue)
- Use **Formulas** to manipulate every value possible
- **Clear error messages** - Probably the best feature
- **Print ready**: PNG with dpi, or one PDF per set with bleed and crop marks
- Easy **Docker** Deployment with `docker compose up --build`

## Quick start

**Run the editor with Docker**

```sh
docker build -t yoshida .
docker run -p 8080:8080 yoshida
```

**Or use a release zip** (prebuilt for Linux, macOS and Windows, nothing to install):

unzip it and run `./start.sh` (Linux), double-click `start.command` (macOS) or `start.bat` (Windows), then open <http://localhost:8080/editor/>.

**Or render from the command line**

```sh
yoshida check  examples/poker
yoshida render examples/poker --out out
```

## Project files

The editor exports a whole project (designs, card files, images and fonts) as a single `.yoshida` file. It is a zip container, like `.docx`, so you can share it, open it again with **Open project file…** or by dropping it on the editor, and unpack it with any archive tool after renaming it to `.zip`. Plain `.zip` projects from older exports still open. See [FORMAT.md](FORMAT.md#project-file-yoshida).

## Build from source

You need [Zig 0.16.0](https://ziglang.org/download/) (or `pip install ziglang==0.16.0`) and, for the editor, Node 22.

```sh
zig build test                        # unit tests
zig build -Doptimize=ReleaseFast      # zig-out/bin/yoshida and zig-out/bin/yoshida-server
zig build wasm                        # zig-out/web/yoshida.wasm and expr.wasm

cd web && npm install
npm run wasm && npm run examples && npm run dev    # editor on http://localhost:5173
```

More in [Building from Source](https://yoshida.xoyz.dev/docs/building-from-source/).

## License

yoshida is released under the [MIT License](LICENSE). Contributions are welcome, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Third-party code

yoshida bundles a few small libraries so that it builds without any C dependencies installed:

| Library                                                              | Used for                                             | License                   |
| -------------------------------------------------------------------- | ---------------------------------------------------- | ------------------------- |
| [stb_image](https://github.com/nothings/stb)                         | Loading PNG, JPEG, GIF and BMP images                | Public domain / MIT       |
| [stb_truetype](https://github.com/nothings/stb)                      | Reading fonts and drawing text                       | Public domain / MIT       |
| [simplewebp](https://github.com/MikuAuahDark/simplewebp)             | Loading WebP images                                  | BSD-3-Clause              |
| [Lato](https://www.latofonts.com)                                    | Default font                                         | SIL Open Font License 1.1 |
| [Noto Sans Symbols 2](https://github.com/notofonts/symbols) (subset) | Fallback for arrows, shapes, stars and other symbols | SIL Open Font License 1.1 |

The C libraries are single-header files in [`src/c/`](src/c). Why they are large and how to update them is described in [`src/c/README.md`](src/c/README.md).

## Documentation

The **[documentation](https://yoshida.xoyz.dev/docs/)** has a page for every feature:

|                                                                                                                                                       |                                                   |
| ----------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| [Getting Started](https://yoshida.xoyz.dev/docs/getting-started/)                                                                                     | First card, in the editor and on the command line |
| [Command Line](https://yoshida.xoyz.dev/docs/command-line/) · [Server and Docker](https://yoshida.xoyz.dev/docs/server-and-docker/)                   | Options, exit codes, the HTTP API                 |
| [Designs](https://yoshida.xoyz.dev/docs/designs/) · [Params](https://yoshida.xoyz.dev/docs/params/) · [Layers](https://yoshida.xoyz.dev/docs/layers/) | The file format                                   |
| [Expressions](https://yoshida.xoyz.dev/docs/expressions/) · [Card Data](https://yoshida.xoyz.dev/docs/card-data/)                                     | Formulas, templates, JSON and CSV                 |
| [Builder](https://yoshida.xoyz.dev/docs/builder/)                                                                                                     | The visual editor, panel by panel, with shortcuts |
| [Diagnostics](https://yoshida.xoyz.dev/docs/diagnostics/)                                                                                             | Every error code and how to fix it                |
| [Architecture](https://yoshida.xoyz.dev/docs/architecture/)                                                                                           | Core, WebAssembly, server                         |
| [Contributing](https://yoshida.xoyz.dev/docs/contributing/) · [Testing](https://yoshida.xoyz.dev/docs/testing/)                                       | Setup, checks, PR titles, releases                |
| [Known Gaps](https://yoshida.xoyz.dev/docs/known-gaps/) · [Privacy](https://yoshida.xoyz.dev/docs/saving-images-and-privacy/)                         | What is missing, and where your data goes         |

Working projects are in [`examples/`](examples): a full poker deck (`poker`) and a printable party board (`board-game`).
