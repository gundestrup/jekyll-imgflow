# Installation Guide

## Quick Start

### 1. Build the Gem

```bash
gem build jekyll-imgflow.gemspec
```

This creates `jekyll-imgflow-0.1.11.gem`

### 2. Install in Your Jekyll Site

```bash
# Navigate to your Jekyll site
cd /path/to/your/jekyll/site

# Install the gem
gem install /path/to/jekyll-imgflow-0.1.11.gem
```

### 3. Add to Gemfile

In your Jekyll site's `Gemfile`:

```ruby
group :jekyll_plugins do
  gem "jekyll-imgflow"
  gem "jekyll_picture_tag", "~> 2.0"
end
```

### 4. Add to _config.yml

**Minimal config** — all you need is `originals` and `output`:

```yaml
imgflow:
  originals: "assets/images/originals"
  output: "assets/images/optimized"
```

That's it. Everything else has sensible defaults:

| Setting | Default | Description |
| --- | --- | --- |
| `quality` | `85` | JPEG/WebP quality (1-100) |
| `backend_priority` | `sharp, libvips, imagemagick, imgproxy, weserv, flyimg` | Provider preference order (first available wins; see [providers.md](providers.md)) |
| `formats` | `avif, webp, png, jpg` | Output formats (priority order — browser picks first supported) |
| `fallback_format` | `jpg` | Format for `<img>` fallback in `<picture>` (all others get `<source>` tags) |
| `sizes` | `sm: 400, md: 800, lg: 1200, xl: 2000` | Responsive widths in pixels |
| `input_formats` | `jpg, jpeg, png, webp, avif, gif, tiff, tif, svg` | Accepted input formats |
| `cache_dir` | `.cache/imgflow` | Persistent manifest directory, excluded from Jekyll output and watch processing |

**Full config** (override any default):

```yaml
imgflow:
  originals: "assets/images/originals"
  output: "assets/images/optimized"
  cache_dir: ".cache/imgflow"
  quality: 85
  backend_priority:
    - sharp
    - libvips
    - imagemagick
    - imgproxy
    - weserv
    - flyimg
  formats:
    - avif
    - webp
    - png
    - jpg
  sizes:
    sm: 400
    md: 800
    lg: 1200
    xl: 2000
  # HTTP provider URLs (only needed if using those providers)
  imgproxy_url: "http://localhost:8080"
  sharp_url: "http://localhost:3000"
```

**Backward compatibility** — if you use `shared_images_configs` (for
jekyll_picture_tag alignment), ImgFlow still merges it as a base layer:

```yaml
shared_images_configs:
  originals: "assets/images/originals"
  output: "assets/images/optimized"

imgflow:
  quality: 90  # override only what you need
```

**Backend priority** determines which provider is used (first available wins).
See [providers.md](providers.md) for the benchmark-ordered comparison.

### 5. Install Image Processing Tools

**Option A: Local Installation (Development)**

```bash
# macOS
brew install imagemagick vips

# Ubuntu/Debian
sudo apt-get install imagemagick libvips-tools
```

**Option B: Docker Services**

```bash
# In the jekyll-imgflow directory
rake start_services
```

### 6. Create Directory Structure

```bash
mkdir -p assets/images/originals
mkdir -p assets/images/optimized
```

### 7. Add Images

Place your original images in `assets/images/originals/`

### 8. Use in Templates

```liquid
{% ImgFlow "photo.jpg", size: "lg", alt: "My photo" %}
```

### 9. Run Jekyll

**Development (processes images):**

```bash
JEKYLL_ENV=development jekyll serve
```

**Production (uses pre-optimized images):**

```bash
jekyll build
```

## Verification

### Test the Installation

```bash
# Start Jekyll in development mode
JEKYLL_ENV=development jekyll serve

# You should see:
# ImgFlow: Processing images in development mode...
```

### Test Docker Services (if using)

```bash
# Check services are running
docker-compose ps

# Test Sharp
curl http://localhost:3000/health

# Test Imgproxy
curl http://localhost:8080/health

# Test CLI tools
docker exec imgflow-tools vips --version
docker exec imgflow-tools convert --version
```

## Troubleshooting

### Gem not found

```bash
# Check gem is installed
gem list jekyll-imgflow

# Reinstall if needed
gem uninstall jekyll-imgflow
gem install /path/to/jekyll-imgflow-0.1.11.gem
```

### Images not processing

1. Check environment: `echo $JEKYLL_ENV`
2. Should be `development` for processing
3. Check logs for provider errors
4. Verify at least one provider is available

### Provider not found

```bash
# Check ImageMagick
convert --version

# Check LibVips
vips --version

# Check Docker services
docker-compose ps
```

## Publishing to RubyGems

Publishing is automated via GitHub Actions trusted publishing. See the
[AGENTS.md Release Process](../AGENTS.md#release-process) section for the
full procedure.

Users can install the published gem with:

```bash
gem install jekyll-imgflow
```

## Development Installation

For development work on the gem itself:

```bash
# Clone the repository
git clone https://github.com/gundestrup/jekyll-imgflow.git
cd jekyll-imgflow

# Install dependencies (runtime deps come from the gemspec via `gemspec`
# directive in the Gemfile; dev deps are declared in the Gemfile)
bundle install

# Build gem
gem build jekyll-imgflow.gemspec

# Install locally
gem install jekyll-imgflow-0.1.11.gem

# Or use in a Jekyll site with local path
# In Jekyll site's Gemfile:
gem "jekyll-imgflow", path: "/path/to/jekyll-imgflow"
```

## Uninstallation

```bash
gem uninstall jekyll-imgflow
```

Remove from your Jekyll site's:

- `Gemfile`
- `_config.yml` plugins section
