# ImgFlow Presets Directory

This directory contains user-defined presets that combine multiple ImgFlow tags into reusable templates.

## 📁 Preset Structure

Presets are Jekyll partials that follow the naming convention: `_IFpreset_name.html`

The `_IF` prefix identifies these as ImgFlow preset files.

## 🎨 Creating Presets

### Example: Hero Image Preset
**File:** `_presets/_IFhero.html`

```liquid
{% imgflow_resize image.jpg width:400 height:300 %}
{% imgflow_resize image.jpg width:800 height:600 %}
{% imgflow_resize image.jpg width:1200 height:900 %}
{% imgflow_resize image.jpg width:1600 height:1200 %}
{% imgflow_format image.jpg formats:avif,webp,jpg %}
{% imgflow_quality image.jpg quality:85 %}
```

### Example: Thumbnail Preset
**File:** `_presets/_IFthumbnail.html`

```liquid
{% imgflow_crop image.jpg ratio:1:1 %}
{% imgflow_resize image.jpg width:100 height:100 %}
{% imgflow_resize image.jpg width:200 height:200 %}
{% imgflow_format image.jpg formats:webp,jpg %}
{% imgflow_quality image.jpg quality:75 %}
```

### Example: Gallery Preset
**File:** `_presets/_IFgallery.html`

```liquid
{% imgflow_resize image.jpg width:300 height:200 %}
{% imgflow_resize image.jpg width:600 height:400 %}
{% imgflow_resize image.jpg width:900 height:600 %}
{% imgflow_format image.jpg formats:avif,webp,jpg %}
{% imgflow_quality image.jpg quality:80 %}
{% imgflow_optimize image.jpg level:high %}
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

### Direct Include
```liquid
{% include _IFhero.html image="banner.jpg" %}
```

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

1. **Parses the preset file** for tag calls
2. **Executes each tag** in sequence
3. **Applies provider fallbacks** if needed
4. **Generates final HTML** with all variants
5. **Caches results** for future use

## 📁 Directory Options

Presets can be stored in multiple locations:

```
_project/
├── _presets/               # Primary location
│   ├── _IFhero.html
│   ├── _IFthumbnail.html
│   └── _IFgallery.html
├── _includes/              # Alternative location
│   ├── _IFhero.html
│   └── _IFthumbnail.html
└── _IFhero.html            # Root level (not recommended)
```

## 🎯 Best Practices

1. **Use descriptive names** - `hero`, `thumbnail`, `gallery`
2. **Include multiple sizes** - At least 3 breakpoints
3. **Use modern formats** - AVIF, WebP, JPG fallback
4. **Set appropriate quality** - 75-85 for most use cases
5. **Test with different providers** - Ensure compatibility

## 🚀 Future Extensibility

The preset system is designed to be easily extended:

- **New tags** can be added to the tag registry
- **New providers** automatically work with existing presets
- **Custom logic** can be added to preset files
- **Conditional processing** based on image properties
