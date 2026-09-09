# ImgFlow Presets Directory

This documentation describes reusable YAML presets. Built-in presets are shipped
with the gem and user-defined presets are loaded from `_data/imgflow/presets/`.
A user preset with the same name overrides the built-in preset.

## 📁 Preset Structure

Presets are YAML files named `<preset_name>.yml` under
`_data/imgflow/presets/`. Built-in presets are available without copying them.
To enable the optional preset-management tasks, add
`require "jekyll-imgflow/tasks"` to the site's `Rakefile`; then run
`rake imgflow:install_presets` to copy editable versions into that directory.

## 🎨 Creating Presets

### Example: Hero Image Preset
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

### Example: Thumbnail Preset
**File:** `_data/imgflow/presets/thumbnail.yml`

```yaml
operations:
  - resize:
      width: 150
  - format:
      formats: ["webp", "jpg"]
  - quality:
      quality: 75
```

### Example: Gallery Preset
**File:** `_data/imgflow/presets/gallery.yml`

```yaml
operations:
  - resize:
      width: 400
  - format:
      formats: ["avif", "webp", "jpg"]
  - quality:
      quality: 80
```

## 🚀 Using Presets

### In Markdown Files
```markdown
![Hero Image]({% imgflow banner.jpg preset:hero %})

{% imgflow thumbnail.jpg preset:thumbnail class="thumb" %}
```

### In Layouts
```liquid
<!-- _layouts/post.html -->
<header>
  {% imgflow page.hero_image preset:hero class="post-header" %}
</header>

<div class="content">
  {{ content }}
</div>

<footer>
  {% imgflow page.thumbnail preset:thumbnail class="author-avatar" %}
</footer>
```

### User overrides

Copy the built-in presets into the site and edit the YAML as needed:

```bash
bundle exec rake imgflow:install_presets
```

A user-defined preset with the same name takes precedence over the built-in
preset. User options supplied on the tag override values from the preset.

## 🏷️ Available Tags

### Core Tags
- `imgflow_resize` - Change image dimensions
  - `width:400` - Set width
  - `height:300` - Set height
  - `maintain_aspect:true` - Keep aspect ratio

- `imgflow_crop` - Crop to aspect ratio
  - `ratio:16:9` - Aspect ratio
  - `x:0 y:0` - Crop position
  - `width:800 height:600` - Specific dimensions

- `imgflow_quality` - Set compression quality
  - `quality:85` - Quality percentage (0-100)

- `imgflow_format` - Convert to different formats
  - `formats:avif,webp,jpg` - List of formats
  - `format:webp` - Single format

- `imgflow_optimize` - General optimization
  - `level:medium` - Optimization level (low, medium, high, maximum)

- `imgflow_watermark` - Add watermarks
  - `watermark:/path/to/watermark.png` - Watermark image
  - `position:bottom_right` - Position
  - `opacity:0.7` - Opacity (0.0-1.0)

## 🔄 Preset Processing

When a preset is called, ImgFlow:

1. Loads a user preset from `_data/imgflow/presets/` when present
2. Otherwise loads the matching built-in YAML preset
3. Converts its operations to ImgFlow options
4. Applies options supplied on the tag as overrides
5. Generates and caches the requested image variants

## 📁 Directory Layout

```text
_project/
├── _data/imgflow/presets/  # Optional user presets (override built-ins)
│   ├── hero.yml
│   ├── thumbnail.yml
│   └── gallery.yml
└── assets/images/          # Site images
```

## 🎯 Best Practices

1. **Use descriptive names** - `hero`, `thumbnail`, `gallery`
2. **Choose dimensions for the intended placement** - Override them on individual tags when needed
3. **Use modern formats** - AVIF, WebP, JPG fallback
4. **Set appropriate quality** - 75-85 for most use cases
5. **Test with different providers** - Ensure compatibility

## 🚀 Future Extensibility

The preset system is designed to be easily extended:

- **New tags** can be added to the tag registry
- **New providers** automatically work with existing presets
- **Custom logic** can be added to preset files
- **Conditional processing** based on image properties
