# ImgFlow Preset Examples

This directory contains example presets that demonstrate the power and flexibility of the ImgFlow preset system.

## 🎨 Hero Image Preset

**File:** `_IFhero.html`

```liquid
<!-- Hero image preset - large, high-quality images for headers -->
{% imgflow_resize image.jpg width:400 height:300 %}
{% imgflow_resize image.jpg width:800 height:600 %}
{% imgflow_resize image.jpg width:1200 height:900 %}
{% imgflow_resize image.jpg width:1600 height:1200 %}
{% imgflow_resize image.jpg width:2000 height:1500 %}
{% imgflow_format image.jpg formats:avif,webp,jpg %}
{% imgflow_quality image.jpg quality:85 %}
```

**Usage:**
```liquid
{% imgflow hero-banner.jpg preset:hero class="hero-image" %}
```

**Result:** Generates 15 image variants (5 sizes × 3 formats) with optimized quality.

---

## 🖼️ Thumbnail Preset

**File:** `_IFthumbnail.html`

```liquid
<!-- Thumbnail preset - square, optimized for small sizes -->
{% imgflow_crop image.jpg ratio:1:1 %}
{% imgflow_resize image.jpg width:50 height:50 %}
{% imgflow_resize image.jpg width:100 height:100 %}
{% imgflow_resize image.jpg width:200 height:200 %}
{% imgflow_format image.jpg formats:webp,jpg %}
{% imgflow_quality image.jpg quality:75 %}
```

**Usage:**
```liquid
{% imgflow avatar.jpg preset:thumbnail class="user-avatar" %}
```

**Result:** Generates 6 square thumbnails (3 sizes × 2 formats) perfect for avatars and galleries.

---

## 🖼️ Gallery Preset

**File:** `_IFgallery.html`

```liquid
<!-- Gallery preset - medium-sized images for photo galleries -->
{% imgflow_resize image.jpg width:300 height:200 %}
{% imgflow_resize image.jpg width:600 height:400 %}
{% imgflow_resize image.jpg width:900 height:600 %}
{% imgflow_resize image.jpg width:1200 height:800 %}
{% imgflow_format image.jpg formats:avif,webp,jpg %}
{% imgflow_quality image.jpg quality:80 %}
{% imgflow_optimize image.jpg level:high %}
```

**Usage:**
```liquid
{% imgflow photo.jpg preset:gallery class="gallery-item" %}
```

**Result:** Generates 12 gallery images (4 sizes × 3 formats) with high optimization.

---

## 📱 Mobile-First Preset

**File:** `_IFmobile.html`

```liquid
<!-- Mobile-first preset - optimized for mobile devices -->
{% imgflow_resize image.jpg width:375 height:667 %}
{% imgflow_resize image.jpg width:750 height:1334 %}
{% imgflow_resize image.jpg width:1125 height:2001 %}
{% imgflow_format image.jpg formats:avif,webp,jpg %}
{% imgflow_quality image.jpg quality:70 %}
{% imgflow_optimize image.jpg level:medium %}
```

**Usage:**
```liquid
{% imgflow mobile-banner.jpg preset:mobile class="mobile-banner" %}
```

**Result:** Generates 9 mobile-optimized images (3 sizes × 3 formats) with smaller file sizes.

---

## 🎨 High-Quality Preset

**File:** `_IFhigh_quality.html`

```liquid
<!-- High-quality preset - maximum quality for professional use -->
{% imgflow_resize image.jpg width:800 height:600 %}
{% imgflow_resize image.jpg width:1600 height:1200 %}
{% imgflow_resize image.jpg width:2400 height:1800 %}
{% imgflow_resize image.jpg width:3200 height:2400 %}
{% imgflow_format image.jpg formats:avif,webp,jpg,png %}
{% imgflow_quality image.jpg quality:95 %}
{% imgflow_optimize image.jpg level:maximum %}
```

**Usage:**
```liquid
{% imgflow professional-photo.jpg preset:high_quality class="pro-photo" %}
```

**Result:** Generates 16 high-quality images (4 sizes × 4 formats) with maximum quality settings.

---

## 🚀 Performance Preset

**File:** `_IFperformance.html`

```liquid
<!-- Performance preset - optimized for fast loading -->
{% imgflow_resize image.jpg width:400 height:300 %}
{% imgflow_resize image.jpg width:800 height:600 %}
{% imgflow_resize image.jpg width:1200 height:900 %}
{% imgflow_format image.jpg formats:avif,webp %}
{% imgflow_quality image.jpg quality:65 %}
{% imgflow_optimize image.jpg level:high %}
```

**Usage:**
```liquid
{% imgflow banner.jpg preset:performance class="perf-banner" %}
```

**Result:** Generates 6 lightweight images (3 sizes × 2 formats) optimized for speed.

---

## 🌊 Blog Post Preset

**File:** `_IFblog.html`

```liquid
<!-- Blog post preset - balanced for blog content -->
{% imgflow_crop image.jpg ratio:16:9 %}
{% imgflow_resize image.jpg width:400 height:225 %}
{% imgflow_resize image.jpg width:800 height:450 %}
{% imgflow_resize image.jpg width:1200 height:675 %}
{% imgflow_format image.jpg formats:avif,webp,jpg %}
{% imgflow_quality image.jpg quality:80 %}
```

**Usage:**
```liquid
{% imgflow blog-image.jpg preset:blog class="blog-image" %}
```

**Result:** Generates 9 blog-optimized images (3 sizes × 3 formats) with 16:9 aspect ratio.

---

## 🖼️ Social Media Preset

**File:** `_IFsocial.html`

```liquid
<!-- Social media preset - optimized for social platforms -->
{% imgflow_crop image.jpg ratio:1:1 %}
{% imgflow_resize image.jpg width:200 height:200 %}
{% imgflow_resize image.jpg width:400 height:400 %}
{% imgflow_resize image.jpg width:800 height:800 %}
{% imgflow_format image.jpg formats:jpg,png %}
{% imgflow_quality image.jpg quality:85 %}
```

**Usage:**
```liquid
{% imgflow social-image.jpg preset:social class="social-preview" %}
```

**Result:** Generates 6 social media images (3 sizes × 2 formats) in square format.

---

## 🎯 Custom Preset Template

**File:** `_IFcustom_template.html`

```liquid
<!-- Custom preset template - modify as needed -->
{% comment %}
  Step 1: Define your sizes (width x height)
  Step 2: Choose your formats (avif, webp, jpg, png)
  Step 3: Set quality (60-95, higher = better quality)
  Step 4: Add optimization level (low, medium, high, maximum)
{% endcomment %}

{% imgflow_resize image.jpg width:400 height:300 %}
{% imgflow_resize image.jpg width:800 height:600 %}
{% imgflow_resize image.jpg width:1200 height:900 %}
{% imgflow_format image.jpg formats:avif,webp,jpg %}
{% imgflow_quality image.jpg quality:80 %}
{% imgflow_optimize image.jpg level:medium %}
```

**Usage:**
```liquid
<!-- Copy this template and modify for your needs -->
{% imgflow your-image.jpg preset:custom_template class="custom-image" %}
```

---

## 🔄 Using Presets in Practice

### In Markdown Files
```markdown
# My Blog Post

![Hero Image]({% imgflow banner.jpg preset:hero %})

## Content with Images

Here's a gallery image:
{% imgflow photo.jpg preset:gallery class="content-image" %}

And a thumbnail:
{% imgflow thumb.jpg preset:thumbnail class="thumb" %}
```

### In Layouts
```liquid
<!-- _layouts/post.html -->
<article class="post">
  <header class="post-header">
    {% imgflow page.hero_image preset:hero class="post-hero" %}
    <h1>{{ page.title }}</h1>
  </header>
  
  <div class="post-content">
    {{ content }}
  </div>
  
  <footer class="post-footer">
    {% imgflow page.author_avatar preset:thumbnail class="author-avatar" %}
    <p>By {{ page.author }}</p>
  </footer>
</article>
```

### In Includes
```liquid
<!-- _includes/gallery.html -->
<div class="gallery">
  {% for image in include.images %}
    <div class="gallery-item">
      {% imgflow image preset:gallery class="gallery-photo" %}
    </div>
  {% endfor %}
</div>
```

---

## 🎯 Preset Best Practices

### ✅ **Do:**
- Use descriptive preset names
- Include multiple breakpoints (at least 3)
- Use modern formats (AVIF, WebP, JPG fallback)
- Set appropriate quality levels
- Test with different image types

### ❌ **Don't:**
- Create presets with only one size
- Use only JPG format
- Set quality too high (wastes bandwidth)
- Forget to test on real devices

### 🎯 **Tips:**
- **Hero images**: Use larger sizes and higher quality
- **Thumbnails**: Use square crops and smaller sizes
- **Galleries**: Balance quality and file size
- **Mobile**: Prioritize smaller file sizes
- **Performance**: Use AVIF + WebP for best compression

---

## 🚀 Advanced Preset Features

### Conditional Processing
```liquid
{% if image contains "portrait" %}
  {% imgflow_crop image.jpg ratio:9:16 %}
{% else %}
  {% imgflow_crop image.jpg ratio:16:9 %}
{% endif %}
```

### Dynamic Quality
```liquid
{% if image contains "photo" %}
  {% imgflow_quality image.jpg quality:85 %}
{% else %}
  {% imgflow_quality image.jpg quality:75 %}
{% endif %}
```

### Format Selection
```liquid
{% if image contains "transparent" %}
  {% imgflow_format image.jpg formats:avif,webp,png %}
{% else %}
  {% imgflow_format image.jpg formats:avif,webp,jpg %}
{% endif %}
```

These examples demonstrate the flexibility and power of the ImgFlow preset system! 🚀
