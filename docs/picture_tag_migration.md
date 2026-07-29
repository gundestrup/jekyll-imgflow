# Picture Tag to ImgFlow - Migration Guide

## Quick Migration (2 steps)

### Step 1: Migrate Presets

```bash
# Preview what will be migrated
bin/imgflow_migrate_presets --preview

# Migrate presets from _data/picture.yml to _data/imgflow/presets/
bin/imgflow_migrate_presets
```

### Step 2: Add Picture Tag Adaptor (Optional)

**Option A: Keep Picture Tags** (Recommended)

- Picture Tag adaptor automatically translates to ImgFlow
- No template changes needed
- Same HTML output as ImgFlow
- Add to `_plugins/picture_tag_hook.rb`:

```ruby
require 'jekyll-imgflow/picture_tag_adaptor'

Jekyll::Hooks.register :pages, :pre_render do |page|
  adaptor = JekyllImgFlow::PictureTagAdaptor.new(page.site, page.site.config)
  page.content.gsub!(/{%\s*picture\s+.+?%}/) do |match|
    adaptor.to_imgflow_tag(match)
  end
end
```

**Option B: Manual Translation**

- Update templates to use ImgFlow syntax
- Use translation table below

**That's it!** Your site now uses ImgFlow with full Picture Tag compatibility.

---

## Syntax Translation

| Picture Tag | ImgFlow | Description |
|-------------|---------|-------------|
| `preset_name image.jpg` | `image.jpg preset:preset_name` | Preset usage |
| `16:9` | `ratio:16:9` | Crop ratio |
| `16:9 center` | `ratio:16:9 position:center` | Ratio + position |
| `--alt "text"` | `alt:"text"` | Alt text |
| `--img class="..."` | `img-class:"..."` | Image attributes |
| `--picture class="..."` | `picture-class:"..."` | Picture attributes |
| `--link "/url"` | `link:"/url"` | Link wrapping |
| `--a class="..."` | `a-class:"..."` | Anchor attributes |
| `--parent class="..."` | `parent-class:"..."` | Parent container |
| `data_auto` | `markup:data_auto` | Lazy loading |
| `picture` | `markup:picture` | Force picture element |

---

## Common Examples

### Hero Image

```liquid
{% imgflow banner.jpg preset:hero ratio:16:9 alt:"Hero Banner" img-class:"hero-image" picture-class:"hero-wrapper" markup:picture %}
```

### Lazy Loaded Image

```liquid
{% imgflow example.jpg img-class:"fade-in" alt:"Lazy loaded" markup:data_img %}
```

### Gallery with Lightbox

```liquid
{% imgflow photo.jpg link:"/images/photo-full.jpg" a-data-lightbox:"gallery" a-class:"gallery-link" img-class:"gallery-thumb" %}
```

### Article Image

```liquid
{% imgflow feature.jpg preset:article ratio:16:9 alt:"Article Feature" img-class:"article-image" %}
```

---

## Preset Migration

### Before (_data/picture.yml)

```yaml
presets:
  hero:
    formats: [webp, original]
    widths: [800, 1200, 1600]
    quality: 90
```

### After (_data/imgflow/presets/hero.yml)

```yaml
name: hero
description: "Migrated from Picture Tag preset 'hero'"
operations:
  - resize:
      width: 1600  # Max width from widths array
  - quality:
      quality: 90
  - format:
      formats: ["webp", "jpg"]
```

---

## CSS Integration

**ImgFlow:**

```liquid
{% imgflow banner.jpg preset:hero ratio:16:9 img-class:"hero-image" picture-class:"hero-wrapper" markup:picture %}
```

**CSS:**

```css
.hero-wrapper {
  position: relative;
  width: 100%;
  max-width: 1200px;
}

.hero-image {
  width: 100%;
  height: auto;
  object-fit: cover;
}
```

---

## JavaScript (Lazy Loading)

**ImgFlow:**

```liquid
{% imgflow example.jpg img-class:"fade-in" alt:"Lazy loaded" markup:data_img %}
```

**Generated HTML:**

```html
<img data-src="..." data-srcset="..." class="fade-in lazy" alt="Lazy loaded">
```

**JavaScript:**

```javascript
import LazyLoad from "vanilla-lazyload";
const lazyLoadInstance = new LazyLoad({
  elements_selector: ".lazy"
});
```

---

## Migration Workflow

1. **Backup your site**
2. **Migrate presets**: `bin/imgflow_migrate_presets --preview` then `bin/imgflow_migrate_presets`
3. **Update templates**: Replace `{% picture` with `{% imgflow` and translate syntax
4. **Test**: `bundle exec jekyll build` and verify images work
5. **Deploy**: Your site now uses ImgFlow!

---

## What's Supported

✅ **All Picture Tag features**:

- Presets, crop ratios, positions
- HTML attributes (img, picture, source, a, parent)
- All markup formats (auto, picture, img, data_auto, etc.)
- Media queries and responsive images
- CSS and JavaScript integration

✅ **Benefits**:

- Better performance
- Unified HTML generation
- Full backward compatibility
- Modern image formats

---

## CLI Tool

```bash
# Preview migration
bin/imgflow_migrate_presets --preview --verbose

# Perform migration
bin/imgflow_migrate_presets --verbose

# Custom site directory
bin/imgflow_migrate_presets --source /path/to/site
```

**See:** [scripts.md](scripts.md) for all available development scripts.

---

## Need Help?

- **Full compatibility**: 100% Picture Tag feature parity
- **Backward compatible**: Existing ImgFlow code unchanged
- **Production ready**: Proper HTML escaping and validation

**Migration complete!** 🎉
