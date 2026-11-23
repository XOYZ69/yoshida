+++
title = "Desktop App"
description = "The editor in a native window, with folders on disk and a built-in renderer."
+++

The desktop app is the [web editor](@/docs/builder.md) in a native window (built with [Tauri 2](https://tauri.app)). It is a **beta**: installers are attached to every [release](https://github.com/XOYZ69/yoshida/releases/latest), but the app has been tested on few machines so far, so expect rough edges and please report them. The projects, the designs and the pixels are the same as in the browser; three things differ.

- **Folders on disk, everywhere.** *Link to folder…* and *Open folder…* use the system's folder dialog on every system, and there are no permission prompts, also not after a restart. Edits are written to the files as you make them, and changes made outside the editor (in another editor, by `git pull`) are offered for reload, as in Chrome. The app can only touch folders you picked, and only files inside them. See [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md#work-on-a-folder-on-your-computer).
- **A built-in renderer.** The app starts `yoshida-server` on `127.0.0.1` and renders ZIP, PDF and whole-design exports with it, using all CPU cores. There is no switch: it is always on, and the progress window says *built-in renderer* instead of *server*. Nothing leaves your computer (the server runs with `--no-telemetry`).
- **"This app", not "this browser".** Projects you do not link to a folder are kept in the app's own storage, separate from any browser.

## Install

### Windows

Download `yoshida_<version>_x64-setup.exe` from the [latest release](https://github.com/XOYZ69/yoshida/releases/latest) and run it. It installs for your user account and needs no administrator rights. The installer is not code-signed yet, so Windows SmartScreen may say *Windows protected your PC*: choose *More info*, then *Run anyway*. Windows 10 and 11 have the WebView2 runtime the app needs; the installer fetches it if it is missing.

### Linux

Download one file from the [latest release](https://github.com/XOYZ69/yoshida/releases/latest):

| File | Use it when |
| --- | --- |
| `yoshida_<version>_amd64.AppImage` | On any distribution: `chmod +x` it and run it. Nothing is installed |
| `yoshida_<version>_amd64.deb` | On Debian, Ubuntu and derivatives: `sudo apt install ./yoshida_<version>_amd64.deb` |
| `yoshida-<version>-1.x86_64.rpm` | On Fedora, openSUSE and derivatives: `sudo dnf install ./yoshida-<version>-1.x86_64.rpm` |

The `.deb` and `.rpm` need WebKitGTK 4.1 (`libwebkit2gtk-4.1`) and GTK 3, which the package manager installs. They are built on Ubuntu 22.04, so they run on systems that are about as new or newer.

### Arch Linux

```sh
git clone https://github.com/XOYZ69/yoshida && cd yoshida/desktop/packaging/arch
makepkg -si
```

`makepkg` builds from the checkout (it needs `cargo`, `nodejs`, `npm` and Zig 0.16.0 on the `PATH`) and installs `yoshida-desktop` with a menu entry and icon. The package depends on `webkit2gtk-4.1` and `gtk3`. Remove it with `sudo pacman -R yoshida-desktop`.

### Any system, from source

See [Building from Source](@/docs/building-from-source.md#desktop-app). On Linux the quickest run, without the Tauri CLI, is:

```sh
cd desktop/src-tauri
cargo build --release --features tauri/custom-protocol
cp binaries/yoshida-server-* target/release/yoshida-server
./target/release/yoshida-desktop
```

`cargo tauri build` makes installers (`.deb`, `.rpm`, `.AppImage`, `.msi`, `.dmg`) in `target/release/bundle/`.

## Use

1. Start **yoshida** from the menu (or `yoshida-desktop`).
2. Open an example or a project, then choose *Link to folder…* in the project menu and pick a folder. The chip beside the export buttons shows the folder name and *in sync*.
3. Edit. The files in the folder change as you work; edit one outside and the editor offers to reload.
4. Export as usual.

## Where things are

| What | Where |
| --- | --- |
| Folders you picked | `folders.json` in the app's config folder (`~/.config/dev.xoyz.yoshida/` on Linux) |
| Projects not linked to a folder | The app's webview storage, tied to port **47810**. If that port is busy the app uses another one and starts with an empty list; the projects are back on the next start on the usual port |
| Server log | The terminal you started the app from |

## Dragging feels slow

On Linux the app clears `WEBKIT_DISABLE_DMABUF_RENDERER` when it starts: with it set, WebKitGTK copies every frame through system memory and dragging and resizing get choppy. If you need it (a blank window on some NVIDIA setups), start the app with `YOSHIDA_KEEP_WEBKIT_ENV=1`. `GDK_BACKEND=x11` is another thing to try.

## Known gaps

- No auto-update: download the new installer for a new version. The Windows installer is not code-signed yet.
- No macOS build yet.
- There is no setting for a remote yoshida server; the app always renders with its own.
- Only Linux has been run by hand so far; the Windows build is made by the release workflow and has not been tried on real machines yet.
