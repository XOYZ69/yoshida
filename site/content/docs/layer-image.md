+++
title = "Layer: image"
description = "Pictures from the project or the web, with fill, contain and cover fitting."
+++

A picture from a file in the project or from the web.

```json
{
  "id": "art",
  "type": "image",
  "src": "{art}",
  "anchor": "top",
  "box": { "x": "50%", "y": "@panel.bounds.top + 60", "w": "80%", "h": 420 },
  "fit": "cover",
  "effects": [{ "type": "fade", "side": "bottom", "length": 120 }]
}
```

Plus the [fields every layer has](@/docs/layers.md).

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `src` | path ([template](@/docs/expressions-templates.md)) | required | Project path or `https://` URL |
| `box` | `{ x, y, w, h }`, number | required | Position and size |
| `fit` | enum | `fill` | `fill` stretches, `contain` letterboxes inside the box, `cover` crops to fill the box |
| `smoothing` | enum | `bilinear` | `nearest` or `bilinear` |

## Supported formats

PNG, JPEG, WebP (lossy and lossless), GIF (first frame) and BMP. Images can be at most 50 megapixels.

## Box with `"auto"`

`w` or `h` (not both) may be the string `"auto"` to keep the image's aspect ratio. Both `"auto"` is error 1110.

```json
"box": { "x": 24, "y": 40, "w": 48, "h": "auto" }
```

`"auto"` only applies to image layers.

## `src` is a template

Because `src` is a template, params can pick the file:

```json
"src": "{art}"
"src": "assets/images/attributes/attribute-{attribute}.png"
```

The result must be a project path or an `https://` URL. If the path is built from a param, the editor cannot rewrite it when you rename a file; the Files tab lists such templates first. See [Builder: Files](@/docs/builder-files.md).

## Missing or unreadable images

- Not found or unreachable: error 4001.
- Found but cannot be decoded: error 4002.

Both stop a normal render. The editor preview (and `yoshida render --preview`) draws a checkered placeholder and continues, so you can keep designing while an image is missing.

## Images from the web

`https://` (and `http://`) images are fetched by the front end, never by the core:

| Front end | Behaviour |
| --- | --- |
| CLI | Downloads each URL once per run (`--offline` turns this off) |
| Editor | The browser downloads it; the remote site must send CORS headers |
| Server | Does not download anything; upload the image with the project (an unreachable URL is error 4001) |

For anything you must be able to reproduce, copy the image into the project instead. See [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md).

## Using an image in expressions

An `image` [param](@/docs/params.md) can be passed to `avg_color(art)` to get the average color of its opaque pixels, for example to tint a frame: `"fill": "mix(avg_color(art), #000000, 0.5)"`. See [Functions](@/docs/expressions-functions.md).

## Reading values

`@art.src` (text), `@art.box.x` ... `@art.box.h`, and the resolved bounds `@art.bounds.*` (after `auto` sizing and anchoring). See [Names and references](@/docs/expressions-names-and-references.md).
