# Vendored C libraries

These files are third-party source code copied into the repository. They are
not written or maintained by this project. Do not edit them by hand; update
them as described below.

| File             | Library                                                 | Version  | License                        | Upstream                                     |
| ---------------- | ------------------------------------------------------- | -------- | ------------------------------ | -------------------------------------------- |
| `stb_image.h`    | stb_image: PNG, JPEG, GIF and BMP decoding              | 2.30     | Public domain / MIT (dual)     | <https://github.com/nothings/stb>            |
| `stb_truetype.h` | stb_truetype: TrueType font parsing and glyph rendering | 1.26     | Public domain / MIT (dual)     | <https://github.com/nothings/stb>            |
| `simplewebp.h`   | simplewebp: WebP decoding                               | 20260718 | BSD-3-Clause (see end of file) | <https://github.com/MikuAuahDark/simplewebp> |

## Why they are so large

Each library is a "single-header" library: the whole implementation lives in
one `.h` file so that it can be dropped into a project without a package
manager. Most of the size is decoder logic and, in the stb files, license text
and comments. Only the code that is actually used ends up in the compiled
binaries.

## How they are built

- `stb_impl.c` is the only place the libraries are compiled. It sets the
  feature switches (for example `STBI_ONLY_PNG`, `STBI_NO_HDR`,
  `STBI_NO_SIMD`) and then includes each header with its `*_IMPLEMENTATION`
  define.
- The binaries are built without a libc. The small headers in `include/`
  (`stdlib.h`, `string.h`, `math.h`, `assert.h`, `stdio.h`) are stubs that map
  the few libc functions the libraries need to yoshida's own implementations.
- Format switches live in `stb_impl.c`. Removing a format there (for example
  GIF or BMP) makes the binaries smaller without touching the vendored files.

## How to update a library

1. Download the new version of the header from the upstream link above.
2. Replace the file in this directory with the downloaded one, unmodified.
3. Update the version in the table above.
4. Run `zig build test`, then render an example (`yoshida render examples/feature-tour --out out`) and check that images and text still look right.
5. If the new version needs additional libc functions, add them to the stubs in `include/`.

## Other bundled third-party files

- `../core/assets/Lato-Regular.ttf`: default font, SIL Open Font License 1.1 (`../core/assets/OFL.txt`), <https://www.latofonts.com>.
