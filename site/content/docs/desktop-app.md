+++
title = "Desktop App"
description = "The editor in a native window, with folders on disk and a built-in renderer."
+++

The desktop app is the [web editor](@/docs/builder.md) in a native window (built with [Tauri 2](https://tauri.app)). It is not part of the releases yet: you build it from source, or on Arch Linux install it as a package. The projects, the designs and the pixels are the same as in the browser; three things differ.

- **Folders on disk, everywhere.** *Link to folder…* and *Open folder…* use the system's folder dialog on every system, and there are no permission prompts, also not after a restart. Edits are written to the files as you make them, and changes made outside the editor (in another editor, by `git pull`) are offered for reload, as in Chrome. The app can only touch folders you picked, and only files inside them. See [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md#work-on-a-folder-on-your-computer).
- **A built-in renderer.** The app starts `yoshida-server` on `127.0.0.1` and renders ZIP, PDF and whole-design exports with it, using all CPU cores. There is no switch: it is always on, and the progress window says *built-in renderer* instead of *server*. Nothing leaves your computer (the server runs with `--no-telemetry`).
- **"This app", not "this browser".** Projects you do not link to a folder are kept in the app's own storage, separate from any browser.

## Install

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

## Known gaps

- No prebuilt downloads and no auto-update yet.
- There is no setting for a remote yoshida server; the app always renders with its own.
- Only Linux has been run so far. macOS and Windows build the same shell but are untested.
