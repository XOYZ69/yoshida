+++
title = "Installation"
description = "Run yoshida in the browser, from the release zip, with Docker or from source."
+++

All of these run the same core and produce the same pixels. Pick by what you want to do.

| You want to | Use |
| --- | --- |
| Try it, or design cards now and then | [The hosted editor](#the-hosted-editor), nothing to install |
| Work offline, or render from scripts | [The release zip](#the-release-zip) |
| Link projects to real folders in any system, with no permission prompts | [The desktop app](@/docs/desktop-app.md) (beta: installers for Windows and Linux) |
| Host the editor for a team or a home lab | [Docker](#docker) |
| Try what comes next | [The dev preview](#the-dev-preview) |
| Change yoshida itself | [Building from Source](@/docs/building-from-source.md) |

## The hosted editor

The editor is online at <https://yoshida.xoyz.dev/editor/>. Everything runs in your browser and your projects stay there; see [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md). A fork that publishes to GitHub Pages gets its own copy at `https://<user>.github.io/<repo>/editor/` ([CI and Deployment](@/docs/ci-and-deployment.md)).

## The release zip

Download the zip of the [latest release](https://github.com/XOYZ69/yoshida/releases/latest) and unpack it. It holds prebuilt programs for Linux (x86_64 and aarch64), macOS (Intel and Apple Silicon) and Windows (x86_64), the editor, these docs, the examples and the JSON Schemas. Nothing else needs to be installed.

| System | Start the editor |
| --- | --- |
| Linux | `./start.sh` |
| macOS | double-click `start.command`, or run `./start.sh` in Terminal |
| Windows | double-click `start.bat` |

Then open <http://localhost:8080/editor/> (on macOS and Windows the start script opens it for you; the docs are at `/docs/`). For another port run `./start.sh 9000` (or `start.bat 9000`). The start scripts listen on `127.0.0.1` only, so only your own computer can reach the editor. To share it, see [Server and Docker](@/docs/server-and-docker.md).

macOS programs are unsigned. `start.sh` clears the quarantine flag; if Gatekeeper still asks, right-click the file and choose Open once.

The command-line tool is in the folder for your system:

```sh
bin/x86_64-linux/yoshida check examples/poker
bin/x86_64-linux/yoshida render examples/poker --out out
```

The folders are `x86_64-linux`, `aarch64-linux`, `x86_64-macos`, `aarch64-macos` and `x86_64-windows` (`yoshida.exe`). Put the folder on your `PATH` to call it as `yoshida`. All options: [Command Line](@/docs/command-line.md).

## Docker

```sh
docker build -t yoshida .
docker run -p 8080:8080 yoshida
```

Then open <http://localhost:8080/editor/> (the landing page is at `/`, the docs at `/docs/`). `docker compose up --build` does the same with the repository's `compose.yaml`. Details and options: [Server and Docker](@/docs/server-and-docker.md).

## The dev preview

The `dev` branch, with what the next release will bring, is published beside the release site: the site at <https://yoshida.xoyz.dev/dev/> and its editor at <https://yoshida.xoyz.dev/dev/editor/>. A red **DEV** stamp beside the logo marks it. It is newer than the latest release and not as well tested, so keep an exported project file of work you care about. How it is built: [CI and Deployment](@/docs/ci-and-deployment.md#deploy-yml).
