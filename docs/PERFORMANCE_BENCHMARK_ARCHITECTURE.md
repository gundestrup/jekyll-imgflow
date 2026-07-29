# Performance Benchmark Architecture

## Overview

The performance benchmark tests ImgFlow's real-world performance by:

1. Running via RSpec test suite (integrated with existing test infrastructure)
2. Using Jekyll API directly to process sites (not shell commands)
3. Testing the actual ImgFlow pipeline (build-time processor, manifest manager, tags)
4. Measuring build times and output sizes with real image generation
5. Generating both markdown and JSON reports

## Design Principles

✅ **Reuse existing infrastructure** - Uses RSpec helpers, TEST_CONFIG, TestPictures
✅ **Dynamic discovery** - Providers, tags, and config loaded at runtime
✅ **Separation of concerns** - Each step has a clear responsibility
✅ **Real pipeline testing** - Uses Jekyll API (`site.process`) to test actual ImgFlow behavior
✅ **No standalone scripts** - Integrated into RSpec test suite for consistency

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Performance Benchmark                       │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Discovery  │    │  Generation  │    │  Validation  │
└──────────────┘    └──────────────┘    └──────────────┘
        │                   │                   │
        ▼                   ▼                   ▼
  RSpec Helpers      Jekyll Build       FastImage Check
  - available_       - create_test_     - validate_image_
    providers          jekyll_site        dimensions
  - TEST_CONFIG      - build_jekyll_    - get_image_
  - TestPictures       site               dimensions
```

## Workflow

### 1. Provider Discovery

```ruby
# Uses: available_providers (RSpec helper)
providers = available_providers
# Returns: [{name: "sharp", class: Sharp, instance: ..., available: true}, ...]
```

### 2. Configuration Loading

```ruby
# Uses: TEST_CONFIG (from test_config.rb)
config = TEST_CONFIG["imgflow"]
input_formats = config.dig("shared_images_configs", "input_formats")
output_formats = config["formats"]
```

### 3. Picture Library Loading

```ruby
# Uses: TestPictures (RSpec helper)
pictures = TestPictures.get(:default_multi)
# Returns: ["file_example-large.jpg", "file_example-large.png", ...]
```

### 4. Test Site Creation

```ruby
# Uses: create_test_jekyll_site (RSpec helper)
test_dir = create_test_dir("performance-benchmark")
create_test_jekyll_site(test_dir, :imgflow_only, { test_images: pictures })
```

### 5. Test Page Generation

```ruby
# Generates MD pages with ImgFlow liquid tags
pictures.each do |picture|
  sizes.each do |size|
    formats.each do |format|
      # Create page with: {% imgflow picture width:size format:format %}
    end
  end
end
```

### 6. Jekyll Build & Benchmark

```ruby
# Uses: build_jekyll_site (RSpec helper)
build_time = Benchmark.realtime do
  build_jekyll_site(test_dir, serve: false)
end
```

### 7. Output Validation

```ruby
# Uses: validate_image_dimensions (RSpec helper)
images.each do |image_path|
  validate_image_dimensions(image_path, expected_width, expected_height)
end
```

### 8. Report Generation

```ruby
# Generate markdown report with:
# - Build times per provider
# - Images generated count
# - Total/average output sizes
# - Compression ratios
```

## Reused Components

### From RSpec Helpers (`spec/spec_helper.rb`)

- `available_providers` - Provider discovery
- `create_test_dir` - Test directory creation
- `create_test_jekyll_site` - Jekyll site setup
- `build_jekyll_site` - Jekyll build execution
- `validate_image_dimensions` - Image validation
- `get_image_dimensions` - Dimension extraction
- `copy_test_images_to_site` - Image copying

### From Test Infrastructure

- `TEST_CONFIG` - Central configuration
- `TestPictures` - Test image library
- `TestDirectoryHelper` - Directory management

### From Rake Tasks

- `rake check_services` - Service availability (via available_providers)

## Benefits

1. **No Code Duplication** - Reuses 100% of existing helpers
2. **Consistency** - Same test setup as RSpec tests
3. **Maintainability** - Changes to helpers benefit both tests and benchmark
4. **Accuracy** - Tests real ImgFlow pipeline, not mocked behavior
5. **Simplicity** - ~200 lines vs ~1300 lines

## Usage

```bash
# Run performance benchmark via RSpec
bundle exec rspec spec/performance_benchmark_spec.rb:69

# The benchmark uses :default (1 image) for quick testing
# To use :default_multi (6 images), modify line 74 in the spec file
```

## Location

The performance benchmark is implemented in:

- **`spec/performance_benchmark_spec.rb`** - Main benchmark implementation (RSpec test)

## Outputs

The benchmark generates two files:

- **`docs/performance/README.Performance.md`** - Human-readable markdown report
- **`docs/performance/benchmark_results.json`** - Machine-readable JSON for CI/CD

## Implementation Details

### Key Changes from Old Implementation

1. **No Standalone Scripts** - Removed `scripts/performance_benchmark.rb` and `scripts/performance_benchmark_v2.rb`
2. **RSpec Integration** - Benchmark runs as part of test suite in `spec/performance_benchmark_spec.rb`
3. **Jekyll API** - Uses `site.process` instead of shell commands for accurate testing
4. **Provider Names** - Uses lowercase names to match provider registry
5. **Real Processing** - Actually generates 122-134 images per provider (vs 0 in old version)

### Code Reduction

- **Old**: ~1300 lines in standalone script
- **New**: ~150 lines in RSpec test
- **Reduction**: 88% less code by reusing existing infrastructure

## Future Enhancements

- [ ] Add manifest manager cache hit/miss metrics
- [ ] Add per-operation performance breakdown
- [ ] Add memory usage tracking
- [ ] Add parallel processing metrics
- [ ] Add compression ratio analysis per format
