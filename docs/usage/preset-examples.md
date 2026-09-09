# ImgFlow Preset Examples

Presets are YAML files under `_data/imgflow/presets/`. Built-in presets work
without installation; copy them only when you want to customize them.

## Enable Preset Rake Tasks

Add this to the site's `Rakefile`:

```ruby
require "jekyll-imgflow/tasks"
```

Then copy editable versions of the built-in presets:

```bash
bundle exec rake imgflow:install_presets
```

See [presets.md](presets.md) for the full preset reference.

## Responsive Hero

**File:** `_data/imgflow/presets/hero.yml`

```yaml
operations:
  - resize:
      width: 800
  - format:
      formats: ["avif", "webp", "jpg"]
  - quality:
      quality: 85
```

```liquid
{% imgflow "headers/sunset.jpg" preset:hero alt:"Sunset over the mountains" %}
```

This generates AVIF and WebP sources plus a JPG fallback in a `<picture>`
element.

## Thumbnail

**File:** `_data/imgflow/presets/custom-thumbnail.yml`

```yaml
operations:
  - resize:
      width: 200
  - format:
      formats: ["webp", "jpg"]
  - quality:
      quality: 75
```

```liquid
{% imgflow "people/profile.jpg" preset:custom-thumbnail alt:"Profile photo" %}
```

## Single-Format Social Image

**File:** `_data/imgflow/presets/social.yml`

```yaml
operations:
  - resize:
      width: 1200
      height: 630
  - format:
      format: jpg
  - quality:
      quality: 85
```

```liquid
{% imgflow "posts/announcement.png" preset:social alt:"Announcement" %}
```

## Override a Preset

Options on the Liquid tag override values from the preset:

```liquid
{% imgflow "gallery/photo.jpg" preset:gallery width:600 quality:90 %}
```

A user preset with the same name as a built-in preset also overrides the
built-in definition.
