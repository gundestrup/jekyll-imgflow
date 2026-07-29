# Installation Guide

## Quick Start

### 1. Build the Gem

```bash
gem build jekyll-imgflow.gemspec
```

This creates `jekyll-imgflow-0.1.0.gem`

### 2. Install in Your Jekyll Site

```bash
# Navigate to your Jekyll site
cd /path/to/your/jekyll/site

# Install the gem
gem install /path/to/jekyll-imgflow-0.1.0.gem
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

```yaml
# Shared image configuration for both ImgFlow and Picture Tag
shared_images_configs:
  # Input sources (original images)
  originals: "assets/images/originals"
  
  # Output destination (optimized images)
  output: "assets/images/optimized"
  
  # Standardized formats for both plugins
  input_formats:
    - jpg
    - jpeg
    - png
    - webp
    - avif
    - gif
    - tiff
    - tif
    - svg
  formats:
    - webp
    - avif
    - jpg
    - png
  
  # Standardized sizes for both plugins
  sizes:
    sm: 400
    md: 800
    lg: 1200
    xl: 2000

# ImgFlow configuration (inherits from shared_images_configs, override here)
imgflow:
  quality: 85
  backend_priority:
    - imgproxy
    - sharp
    - imagemagick
    - libvips
    - weserv
    - flyimg
  imgproxy_url: "http://192.168.1.50:8080"
  sharp_url: "http://192.168.1.51:3000"

# Picture Tag configuration (uses same paths as shared_images_configs)
picture:
  source: "assets/images/originals"
  output: "assets/images/optimized"
  disabled: false
  ignore_missing_images: true
  presets:
    default:
      formats:
        - webp
        - avif
        - jpg
        - png
      widths: [400, 800, 1200, 2000]
```

ImgFlow automatically merges `shared_images_configs` as defaults. You only need to specify `imgflow:` settings that are specific to ImgFlow (quality, backend priority, provider URLs). To override any shared value (e.g. a different output path), add it under `imgflow:`.

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
docker-compose up -d
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
gem install /path/to/jekyll-imgflow-0.1.0.gem
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

## Publishing to RubyGems (Optional)

To publish the gem publicly:

1. Update gemspec with your details:
   - `s.authors`
   - `s.email`
   - `s.homepage`

2. Create RubyGems account at <https://rubygems.org>

3. Build and push:

```bash
gem build jekyll-imgflow.gemspec
gem push jekyll-imgflow-0.1.0.gem
```

1. Users can then install with:

```bash
gem install jekyll-imgflow
```

## Development Installation

For development work on the gem itself:

```bash
# Clone the repository
git clone https://github.com/yourusername/jekyll-imgflow.git
cd jekyll-imgflow

# Install dependencies
bundle install

# Build gem
gem build jekyll-imgflow.gemspec

# Install locally
gem install jekyll-imgflow-0.1.0.gem

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
