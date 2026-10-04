# README TODO — Gallery Feature

## Gallery module (`JekyllImgFlow::Gallery`) — OPEN

A Piwigo-inspired static gallery feature for ImgFlow. Users drop images into
folders (one folder = one album), add an optional `_album.md` sidecar with
titles/descriptions/tags, and the plugin builds an album index + album pages
with thumbnails, a lightbox, and (later) metadata display and search.

All image processing piggybacks on existing ImgFlow infrastructure: providers,
`ManifestManager`, `FilenameGenerator`, `HtmlGenerator`, `ModalAssets`, and the
`:pre_render` build-time pipeline. No second thumbnail engine.

## References

- [jekyll-gallery-generator](https://github.com/ggreer/jekyll-gallery-generator) —
  `Jekyll::Generator` + per-directory album pages + `galleries:` config map
  (cover, name, hidden, sort_reverse). Take the page-generation shape and
  per-album config pattern; skip the RMagick/exifr pipeline (ImgFlow replaces it).
- [waywardmark: Jekyll gallery without plugins](https://waywardmark.com/blog/add-photo-gallery-to-jekyll) —
  pure-Liquid `_includes` grid over `site.static_files` + `object-fit: cover`
  CSS tiles. Take the CSS grid approach for uniform thumbs (no extra variants).
- [janbum.py gist](https://gist.github.com/jan-vandenberg/55af74584d5844498845078d49b7455e) —
  standalone Python generator. Take: `cover.*` file convention, EXIF
  `DateTimeOriginal` sort with mtime fallback, two-tier output (thumb + large),
  PhotoSwipe `data-pswp-width/height` anchor attrs, index cards with photo
  counts, HEIC input support, EXIF orientation handling (see gap below).
- [Piwigo](https://piwigo.org) — feature target: nested albums, naming/title
  rules, metadata display (EXIF/IPTC), keyword tags, metadata search.

## Decisions

### In-place module, not a separate gem — DECIDED

The gallery couples to ImgFlow *internals* (`site.imgflow_components`,
manifest lookups, filename hashing, hook ordering), not a public API. A
separate `jekyll-imgflow-gallery` gem would need conservative version pins
and coordinated releases forever, plus a duplicated test harness. In-place
keeps one pipeline, one version, one test suite; a clean
`JekyllImgFlow::Gallery` namespace can still be extracted later if it ever
outgrows the gem. Bundler has no feature flags and RubyGems has no extras —
activation is `imgflow.gallery.enabled` in `_config.yml`, the standard Jekyll
pattern.

### Sidecar file is `_album.md` — DECIDED

A `*.md` file with front matter inside `assets/` would be picked up by Jekyll
as a Page and rendered to `_site/.../album/info.html`; without front matter it
is copied as a static file and leaks into output. A leading underscore makes
Jekyll ignore it entirely; the plugin reads it directly.

Structure: YAML front matter for data, markdown body for the album
description (rendered via Jekyll's markdown converter).

```yaml
---
title: Japan Trip
cover: IMG_0690.JPG        # overrides cover.* convention
sort: date_taken           # date_taken | name | manual
hidden: false
images:
  IMG_1039.JPG:
    title: "Temple gate"
    caption: "Fushimi Inari at dusk"
    tags: [kyoto, temple]
---
Free-text album description rendered above the grid.
```

### Image resolution happens at render time, not generate time — DECIDED

Jekyll generators run before ImgFlow's `:pre_render` processing, so at
generate time the manifest only reflects the *previous* build. Therefore:

- `GalleryGenerator` (`Jekyll::Generator`) handles page scaffolding only:
  album discovery, `_album.md` parsing, index + album page creation.
- `{% gallery album_name %}` (a `Liquid::Tag`) resolves each image's versions
  at render time via `site.imgflow_components[:manifest]` — where specialized
  versions are created on demand and `used_on` is recorded so orphan cleanup
  leaves gallery images alone.
- Do not predict output filenames in the generator (the MD5 hash scheme is
  internal); do not emit gallery image markup outside the render path (usage
  would not be tracked and files could be cleaned).

### Album = subdirectory of `imgflow.originals` — DECIDED

`find_original_images` already globs recursively and `output_subdir` already
preserves subdirectories in output paths, so
`originals/japan_trip/foo.jpg` → `optimized/japan_trip/foo-600-<hash>.avif`
works today. Arbitrary nesting gives Piwigo-style sub-albums for free.

### `cover.*` convention + front-matter override — DECIDED

`cover.jpg` (any input extension) in a folder is the album card and is
excluded from the grid. `_album.md` `cover:` overrides; default is the first
sorted image.

## User-facing spec

- Images live in `assets/images/originals/<album>/` (or configured `originals`).
- Optional `_album.md` per folder; folder name humanized as fallback title.
- Gallery tiers via config: thumbnail + 600px + 1200px (AVIF), sizes and
  formats fully configurable.
- `fullsize` mode controls the click target:
  - `avif` — full-res converted AVIF (default; saves space — see excludes).
  - `original` — link/serve the untouched original file.
  - `modal` — built-in ImgFlow modal (`ModalAssets`, self-contained).
  - `photoswipe` — PhotoSwipe 5 lightbox (swipe/zoom/keyboard), needs
    `data-pswp-width/height` from `FastImage.size` (already a dependency).
- Auto-generated pages: gallery index (album cards: cover, title, count) and
  one page per album. Layouts shipped in gem, overridable in site `_layouts/`.
- Optional per-photo detail pages (phase 3) for full metadata display.

## Config sketch

```yaml
imgflow:
  gallery:
    enabled: false            # master switch; everything below inert when off
    url: "/photos"            # base URL for generated pages
    title: "Photos"
    sizes: { thumb: 300, md: 600, lg: 1200 }
    formats: [avif, jpg]      # jpg = <img> fallback; avif-first <source>
    fullsize: avif            # avif | original | modal | photoswipe
    naming: auto              # sidecar | filename | exif (phase 3)
    sort: date_taken          # date_taken | name
    search: false             # phase 3: emit gallery-index.json + JS
    tag_pages: false          # phase 3: /photos/tags/<tag>/ pages
    metadata_fields: [title, keywords, camera, lens, iso, aperture,
                      shutter_speed, focal_length, date_taken]
    # gps excluded by default — decide deliberately before publishing
    albums:
      secret_stuff: { hidden: true }
      japan_trip:  { sort_reverse: true }
```

When `fullsize: avif`, also exclude the originals dir from `_site` output
(Jekyll `exclude:`) — originals stay readable at build time but are not
published. That is where the space saving (and accidental EXIF/GPS
publication avoidance) actually happens.

## Proposed file layout

```text
lib/jekyll-imgflow/
├── gallery.rb                    # requires, config-gated load
└── gallery/
    ├── album.rb                  # folder + _album.md + cover.* → album model
    ├── generator.rb              # Jekyll::Generator: index + album pages
    ├── gallery_tag.rb            # {% gallery name %} — render-time resolution
    ├── grid_generator.rb         # grid <picture> markup via HtmlGenerator
    ├── metadata.rb               # phase 3: EXIF/IPTC reader, digest-cached
    └── search_index.rb           # phase 3: gallery-index.json emitter
```

Layouts shipped under `lib/jekyll-imgflow/gallery/layouts/` (or a documented
copy step): `imgflow_gallery_index.html`, `imgflow_gallery_album.html`,
`imgflow_gallery_photo.html`.

## Technical notes / integration points

- `site.imgflow_components` (set by `BuildTimeProcessor` at `:pre_render`,
  lazily by `ImgflowTag`) provides `config`, `manifest`, `path_resolver`,
  `filename_generator`, `operation_processor`.
- Thumbnail lookup: `manifest.get_version_output(original, {width: 600,
  format: "avif", quality: 85})`; gallery-only sizes register as `:specialized`
  versions with `used_on` pointing at the album page.
- `{% imgflow %}` does NOT resolve Liquid variables (`Parser.parse` ignores
  context) — a layout cannot loop `page.images` through it. Hence the
  dedicated `{% gallery %}` tag. (Variable resolution in `Parser` is a
  separate small improvement worth doing anyway.)
- Uniform tiles: prefer CSS `object-fit: cover` (waywardmark); optional
  server-side squares via existing `crop` tag with `ratio: 1:1`.
- Multi-level albums: nested dirs → nested albums; index shows hierarchy.

## Known gap: EXIF orientation

ImgFlow currently has **no orientation handling** — no `auto-orient`/`rotate`
anywhere in `lib/`. Phone photos with EXIF orientation may render sideways
depending on provider defaults: `vipsthumbnail` and imgproxy/weserv
auto-rotate by default; sharp and ImageMagick need explicit flags
(`rotate()` / `-auto-orient`). Normalize orientation explicitly per provider
so output is consistent — this affects `{% imgflow %}` too, so it belongs in
the providers, not the gallery module.

## Other gaps to close

- `input_formats` lacks `heic`/`heif` (iPhone photos). Provider-dependent
  (sharp needs libheif, ImageMagick needs the delegate) — gate via
  `supported_input_format?`.
- Metadata extraction needs a new dependency:
  - `exifr` — pure Ruby, JPEG/TIFF only, low-risk hard dependency.
  - `mini_exiftool` — full EXIF/IPTC/XMP/GPS via the `exiftool` binary;
    lazy-require (`begin/rescue LoadError`) and degrade gracefully, same
    pattern as provider `available?` checks.

## Security checklist

- Path traversal: validate `{% gallery <name> %}` resolves under
  `originals/` (`expand_path` + `start_with?`), same discipline as
  `GeneratedFileCleaner`.
- `_album.md` front matter: safe YAML only (`YAML.safe_load` / Jekyll's
  front matter parser), never `YAML.load`.
- EXIF/IPTC is **untrusted input** (comes from image files): escape all
  metadata rendered into HTML and the search index (`HtmlGenerator`
  escapes attributes already; apply the same to text content).
- `mini_exiftool` calls: array-form `system`/`Open3` args, never string
  interpolation — filenames are attacker-influenceable.
- GPS: keep out of `metadata_fields`/search index by default.
- New deps go through `bundler_audit` (`rake bundler_audit`).

## Implementation phases

1. **Core**: `imgflow.gallery` config + `Album` model + `_album.md` parsing +
   `cover.*` + `{% gallery %}` tag emitting grid markup through
   `HtmlGenerator` + `fullsize` modes (`avif`/`original`/`modal`).
2. **Pages**: `GalleryGenerator` emitting index + album pages with shipped,
   overridable layouts; hidden albums; nested albums.
3. **Piwigo layer**: EXIF reader (digest-cached in manifest or sidecar JSON),
   per-photo pages with metadata display, `date_taken` sort, tag pages,
   `gallery-index.json` + client-side search JS.
4. **Cross-cutting**: EXIF orientation normalization in providers, `heic`/`heif`
   input support, optional PhotoSwipe lightbox, `{% imgflow %}` Liquid-variable
   resolution.

## Open questions

- Per-photo detail pages vs grid + lightbox only (phase 3 decision).
- `exifr` (simple, limited) vs `mini_exiftool` (rich, external binary).
- Search: JSON + JS filter vs generated tag pages vs both.
- Gallery-scoped vs global `sizes`/`formats` defaults (scoped config shown
  above; global config works today with zero new code).
