# Test Pictures System

Centralized test image fixture management for consistent and flexible testing.

## Overview

The `TestPictures` module provides a categorized catalog of test images with metadata, allowing tests to easily select appropriate images based on format, size, or test scenario.

## Architecture

```
TestPictures Module
├── CATALOG - Image metadata (format, size, type, hash, expected_defaults, expected_specialized)
├── SETS - Predefined image collections (static arrays and dynamic lambdas)
└── Methods - Query, access, and validate images
```

## Available Image Sets

### Quick Test Sets (Fast)
- **`:default`** - Single reliable image (mars-crater-large.jpg)
- **`:default_small`** - Smallest test image (spider_web-small.jpg)
- **`:default_multi`** - One of each common format (jpg, png, webp, tiff, avif, svg) - 6 images
- **`:quick`** - Minimal set for fast tests, one of each format (6 images)

### Format-Specific Sets
- **`:jpg`** - All JPEG images
- **`:png`** - All PNG images
- **`:webp`** - All WebP images
- **`:tiff`** - All TIFF images
- **`:avif`** - All AVIF images
- **`:svg`** - All SVG images

### Size-Specific Sets (One per format)
- **`:small`** - Smallest images, one of each format
- **`:medium`** - Medium images, one of each format
- **`:large`** - Large images, one of each format

### Comprehensive Sets
- **`:full`** - All supported formats (jpg, png, webp, tiff, avif)
- **`:all`** - Every image in the catalog

## Usage in Tests

### Basic Usage

```ruby
# Use default multi-format set
copy_test_images_to_site(originals_dir)

# Use specific set
copy_test_images_to_site(originals_dir, :jpg)

# Use custom array
copy_test_images_to_site(originals_dir, ["mars-crater-large.jpg"])
```

### Environment Variable Control

Run tests with different image sets:

```bash
# Quick test (default)
bundle exec rspec

# Test with only JPG images
TEST_PICTURES=jpg bundle exec rspec

# Test with small images
TEST_PICTURES=small bundle exec rspec

# Full comprehensive test
TEST_PICTURES=full bundle exec rspec

# Test all images
TEST_PICTURES=all bundle exec rspec
```

### Querying Images

```ruby
# Get images for a set
TestPictures.get(:jpg)  # => ["mars-crater-large.jpg", ...]

# Get metadata
TestPictures.metadata("mars-crater-large.jpg")
# => { format: :jpg, size: :large, type: :photo, hash: "f33ea0792", expected_defaults: {...} }

# Check if image exists
TestPictures.exists?("mars-crater-large.jpg")  # => true

# Get full path
TestPictures.path("mars-crater-large.jpg")
# => "spec/fixtures/originals/mars-crater-large.jpg"

# Get images by format
TestPictures.by_format(:png)  # => ["file_example-large.png", ...]

# Get images by size
TestPictures.by_size(:small)  # => ["spider_web-small.jpg", ...]

# List all available set names
TestPictures.available_sets  # => [:default, :default_small, :default_multi, :jpg, ...]

# Get hash for filename generation testing
TestPictures.hash("mars-crater-large.jpg")  # => "f33ea0792"
```

### Test Mode and Dynamic Selection

```ruby
# Get current test mode from environment (TEST_PICTURES or TEST_MODE env var)
TestPictures.test_mode  # => :default

# Get images for current test mode
TestPictures.for_test  # => ["mars-crater-large.jpg"]
```

### Expected Filename and Output Path Helpers

These methods use the `hash` and `expected_defaults` metadata in the catalog to predict output filenames for manifest and filename generation testing.

```ruby
# Get expected output filename for a size/format combination
TestPictures.expected_filename("mars-crater-large.jpg", :sm, :webp)
# => "mars-crater-large-400-f33ea0792.webp"

# Get specialized filename (parser behavior: no quality unless specified)
TestPictures.specialized_filename("mars-crater-large.jpg", :sm, :webp)
# => "mars-crater-large-400-a89ee2bc2.webp"

# Get all expected defaults for an image
TestPictures.expected_defaults("mars-crater-large.jpg")
# => { sm: { webp: "...", avif: "...", jpg: "...", png: "..." }, md: {...}, ... }

# Get expected defaults for a specific size
TestPictures.expected_defaults("mars-crater-large.jpg", :sm)
# => { webp: "...", avif: "...", jpg: "...", png: "..." }

# Get expected defaults for a specific size and format
TestPictures.expected_defaults("mars-crater-large.jpg", :sm, :webp)
# => "mars-crater-large-400-f33ea0792.webp"

# Get full expected output path
TestPictures.expected_output_path("mars-crater-large.jpg", :sm, :webp)
# => "assets/images/optimized/mars-crater-large-400-f33ea0792.webp"
```

### Mock Task Generation

```ruby
# Generate mock completed tasks for testing manifest/processor logic
TestPictures.mock_completed_tasks("mars-crater-large.jpg", sizes: [:sm, :md], formats: [:webp, :avif])
# => [{ task: { original_name: "...", params: {...} }, result: "..." }, ...]
```

## Image Catalog

Each catalog entry includes metadata fields:
- `format` - Image format symbol (`:jpg`, `:png`, `:webp`, `:tiff`, `:avif`, `:svg`)
- `size` - Size category (`:small`, `:medium`, `:large`)
- `type` - Image type (`:photo`, `:sample`, `:artificial`, `:vector`)
- `hash` - (optional) MD5-based hash used in filename generation
- `expected_defaults` - (optional) Expected output filenames per size/format for default quality
- `expected_specialized` - (optional) Expected output filenames for parser behavior (no quality unless specified)

Sizes map to pixel widths: `:sm` => 400, `:md` => 800, `:lg` => 1200, `:xl` => 2000

### JPEG Images
- `mars-crater-large.jpg` - Large photo
- `spider_web-large.jpg` - Large photo
- `spider_web-small.jpg` - Small photo
- `artificial-large.jpg` - Large artificial
- `artificial-small.jpg` - Small artificial
- `file_example-large.jpg` - Large sample
- `file_example-small.jpg` - Small sample

### PNG Images
- `file_example-large.png` - Large sample
- `file_example-small.png` - Small sample

### WebP Images
- `file_example-large.webp` - Large sample
- `file_example-medium.webp` - Medium sample
- `file_example-small.webp` - Small sample

### TIFF Images
- `file_example-large.tiff` - Large sample
- `file_example-medium.tiff` - Medium sample
- `file_example-small.tiff` - Small sample

### AVIF Images
- `ayousef-espanioly.avif` - Medium photo
- `parrot-avif.avif` - Small photo

### SVG Images
- `file_example-medium.svg` - Medium vector
- `file_example-small.svg` - Small vector

## Benefits

1. **Consistency** - All tests use the same categorized images
2. **Flexibility** - Easy to switch between quick and comprehensive tests
3. **Maintainability** - Single source of truth for test images
4. **Performance** - Quick tests use minimal images
5. **Coverage** - Full tests cover all formats and sizes
6. **Documentation** - Clear metadata for each image

## Test Strategy

### Development (Quick)
```bash
# Fast tests with minimal images
bundle exec rspec
# or
TEST_PICTURES=quick bundle exec rspec
```

### CI/CD (Comprehensive)
```bash
# Full format coverage
TEST_PICTURES=full bundle exec rspec
```

### Debugging Specific Formats
```bash
# Test only PNG handling
TEST_PICTURES=png bundle exec rspec

# Test only large images
TEST_PICTURES=large bundle exec rspec
```

## Adding New Images

1. Add image to `spec/fixtures/originals/`
2. Add entry to `CATALOG` in `test_pictures.rb`:
   ```ruby
   "new-image.jpg" => { format: :jpg, size: :large, type: :photo }
   ```
3. For images used in manifest/filename testing, also add `hash`, `expected_defaults`, and optionally `expected_specialized`:
   ```ruby
   "new-image.jpg" => {
     format: :jpg, size: :large, type: :photo,
     hash: "abc123def",
     expected_defaults: {
       sm: { webp: "new-image-400-abc123def.webp", ... },
       md: { webp: "new-image-800-abc123def.webp", ... },
       lg: { webp: "new-image-1200-abc123def.webp", ... },
       xl: { webp: "new-image-2000-abc123def.webp", ... }
     }
   }
   ```
4. Image automatically available in format/size sets
5. Optionally add to custom sets in `SETS`

## Integration with _config.yml

The system aligns with `_config.yml` structure:
- Uses `originals` path from shared config
- Supports all `input_formats` from config
- Provides images for all configured formats

This ensures tests match production configuration.
