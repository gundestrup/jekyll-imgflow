# `{% imgflow %}` Tag Options

Everything after the image path is a `key:value` option. Quoted values are
supported (`alt:"A long caption"`).

```liquid
{% imgflow posts/photo.jpg width:800 alt:"Alt text" %}
{% imgflow x.jpg preset:gallery ratio:16:9 class:"hero" %}
{% imgflow logo.png format:png modal:false link:"https://example.com" %}
```

## Operations

| Option | Default | Description |
| ------ | ------- | ----------- |
| `preset:` | — | Named preset (`gallery`, `hero`, `thumbnail`, or a site preset) |
| `width:` | preset/original | Target width in px |
| `height:` | — | Target height in px |
| `ratio:` | — | Crop to aspect ratio (`16:9`, `1:1`) |
| `aspect_ratio:` | — | Alias of `ratio:` |
| `keep:` | — | `keep:true` maintains the aspect ratio when resizing |
| `position:` | center | Crop/watermark position (`bottom_right`, …) |
| `quality:` | provider default | Compression quality 0–100 (per-format via `optimize_qualities` config) |
| `format:` | — | Single output format (`webp`, `avif`, `jpg`, `png`) |
| `formats:` | config | Comma-separated output format list |
| `optimize` | — | Run the optimize operation |
| `level:` | `medium` | Optimization level |
| `watermark:` | — | Watermark text/image |
| `opacity:` | — | Watermark/alpha opacity 0.0–1.0 |

## HTML attributes

| Option | Default | Description |
| ------ | ------- | ----------- |
| `alt:` | — | `alt` text — keep it meaningful |
| `class:` | — | CSS classes on the `<img>`/`<picture>` |
| `title:` | — | `title` attribute |
| `loading:` | — | `lazy` or `eager` |
| `link:` | — | Wrap the image in `<a href="…">` — use with `modal:false` |
| `modal:` | `image_modal` config (`true`) | Click-to-zoom; `modal:false` disables per image |

## Output markup (`markup:`)

| Value | Emits |
| ----- | ----- |
| `img` | Plain `<img>` — the default |
| `picture` / `auto` | `<picture>` with `<source>` per format |
| `data_img` / `data_auto` | `<img>` with `data-*` sources (lazy/picture-tag compat) |
| `data_picture` | `<picture>` with `data-*` sources |
| `direct_url` | Only the image URL — no element (for `content:`/`style:` use) |
| `naked_srcset` | Only a `srcset` attribute value |

## Notes

- `width:` is required for actual resizing — a bare `{% imgflow %}` emits a
  plain `<img>` of the *unoptimized* original.
- Multi-format output automatically upgrades the markup to `<picture>` when
  more than one result exists.
- Tags emit multi-line block HTML — do not use inside markdown table rows;
  use `markup:direct_url` or a plain `![]()` there.
- The modal lightbox only wraps HTML elements (`img`/`picture`), never
  `direct_url`/`naked_srcset` output. Its CSS/JS is injected once into pages
  that contain `data-imgflow-modal` triggers.

**Related:** [presets.md](presets.md) (preset definitions),
[picture_tag_migration.md](../picture_tag_migration.md) (Jekyll Picture Tag
compatibility syntax such as `img-class:`/`picture-class:`/`markup:data_img`).
