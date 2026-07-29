# Test Helper Methods Reference

This document describes all standardized helper methods available in `spec_helper.rb` to eliminate code duplication and improve test consistency.

## Component Creation Helpers

### `create_imgflow_components(site)`
Creates all standard ImgFlow components from a site object.

**Returns:** Hash with keys:
- `:config` - JekyllImgFlow::Config instance
- `:registry` - ProviderRegistry instance
- `:provider` - Current provider instance
- `:path_resolver` - PathResolver instance
- `:operation_processor` - OperationProcessor instance
- `:batch_manager` - BatchManager instance
- `:manifest_manager` - ManifestManager instance
- `:manifest` - Alias for `:manifest_manager` (backward compatibility)

**Example:**
```ruby
let(:components) { create_imgflow_components(site) }
let(:config) { components[:config] }
let(:batch_manager) { components[:batch_manager] }
```

### `create_batch_task(original_name, input_path, output_path, options = {})`
Creates a standard batch task definition.

**Parameters:**
- `original_name` - Original image filename
- `input_path` - Path to input image
- `output_path` - Path to output image
- `options` - Optional parameters:
  - `:operation_type` - Operation type (default: `:resize`)
  - `:params` - Operation parameters (default: `{ width: 800 }`)
  - `:version_type` - Version type (default: `:default`)
  - `:page_path` - Page path (default: `nil`)
  - `:skip_if_exists` - Skip if exists (default: `true`)

**Example:**
```ruby
task = create_batch_task("image.jpg", "/path/to/input.jpg", "/path/to/output.jpg")
```

### `create_simple_mock_site(config)`
Creates a simple `MockSite` struct for testing (used in site generation).

**Parameters:**
- `config` - Site configuration hash

**Returns:** `MockSite` struct with `config` attribute

**Example:**
```ruby
mock_site = create_simple_mock_site(TEST_CONFIG)
```

## Mock Object Helpers

### `create_mock_site(options = {})`
Creates a mock Jekyll site for testing.

**Options:**
- `:config` - Site configuration (default: `TEST_CONFIG`)
- `:source` - Site source directory (default: `"/tmp/test_site"`)
- `:dest` - Site destination directory (default: `"#{source}/_site"`)

**Example:**
```ruby
let(:site) { create_mock_site(source: test_dir) }
```

### `create_mock_page(options = {})`
Creates a mock Jekyll page for testing.

**Options:**
- `:url` - Page URL (default: `"/test-page.html"`)
- `:path` - Page path (default: `"/test-page.html"`)

**Example:**
```ruby
let(:page) { create_mock_page(url: "/blog/post.html") }
```

### `create_mock_context(site, options = {})`
Creates a mock Liquid context for testing.

**Parameters:**
- `site` - Site object to register
- `options` - Optional registers to merge

**Example:**
```ruby
let(:context) { create_mock_context(site) }
```

## Test Image Helpers

### `fixture_image_path(filename = nil)`
Gets path to a test fixture image.

**Parameters:**
- `filename` - Image filename (default: first image from `TestPictures.get(:default)`)

**Returns:** Absolute path to fixture image

**Example:**
```ruby
let(:test_image) { fixture_image_path("mars-crater-large.jpg") }
let(:default_image) { fixture_image_path } # Uses TestPictures.default
```

### `fixture_image_paths(set = :default_multi)`
Gets multiple fixture image paths.

**Parameters:**
- `set` - TestPictures set name (default: `:default_multi`)

**Returns:** Array of absolute paths

**Example:**
```ruby
let(:test_images) { fixture_image_paths(:default_multi) }
```

### `get_processor_components(processor)`
Extracts internal components from a `BuildTimeProcessor` instance.

**Parameters:**
- `processor` - `JekyllImgFlow::BuildTimeProcessor` instance

**Returns:** Hash with keys:
- `:manifest` - ManifestManager instance
- `:site_dest` - Site destination directory
- `:batch_manager` - BatchManager instance
- `:operation_processor` - OperationProcessor instance

**Example:**
```ruby
components = get_processor_components(processor)
manifest = components[:manifest]
```

### `create_test_dir(name = nil)`
Creates a test directory using the centralized `TestDirectoryHelper` system.

**Parameters:**
- `name` - Optional name suffix for the directory

**Returns:** String path to the created directory

**Example:**
```ruby
let(:test_dir) { create_test_dir("my_test") }
```

### `copy_test_images_to_site(originals_dir, image_set = :default_multi, fallback: :default_multi)`
Copies test images to a site's originals directory.

**Parameters:**
- `originals_dir` - Destination directory for images
- `image_set` - Symbol name or Array of filenames (default: `:default_multi`)
- `:fallback` - Fallback set if `image_set` not found (default: `:default_multi`)

**Example:**
```ruby
copy_test_images_to_site(originals_dir, :jpg)
copy_test_images_to_site(originals_dir, ["mars-crater-large.jpg"])
```

### `expect_valid_output_file(file_path, min_size = 1000)`
Validates that an output file exists and has a reasonable size.

**Parameters:**
- `file_path` - Path to the output file
- `min_size` - Minimum expected file size in bytes (default: `1000`)

**Example:**
```ruby
expect_valid_output_file(output_path)
expect_valid_output_file(output_path, min_size: 500)
```

### `expect_file_signature(file_path, expected_format)`
Validates that a file matches the expected image format using `FastImage` with extension fallback.

**Parameters:**
- `file_path` - Path to the image file
- `expected_format` - Expected format as string (e.g. `"webp"`, `"avif"`, `"jpg"`)

**Example:**
```ruby
expect_file_signature(output_path, "webp")
```

## Specialized Setup Helpers

### `create_tag_test_setup(tag_class, options = {})`
Creates complete tag test setup (site, config, provider, tag).

**Parameters:**
- `tag_class` - Tag class to instantiate
- `options` - Optional site configuration

**Returns:** Hash with keys:
- `:site` - Mock site object
- `:config` - Config instance
- `:provider` - Provider instance
- `:tag` - Tag instance

**Example:**
```ruby
let(:setup) { create_tag_test_setup(JekyllImgFlow::Tags::ResizeTag) }
let(:tag) { setup[:tag] }
let(:provider) { setup[:provider] }
```

### `create_test_setup_with_config(custom_config, options = {})`
Creates test setup with custom configuration.

**Parameters:**
- `custom_config` - Custom config to merge with TEST_CONFIG
- `options` - Optional parameters

**Returns:** Hash with keys:
- `:site` - Mock site object
- `:config` - Config instance
- `:components` - All ImgFlow components

**Example:**
```ruby
custom = { "imgflow" => { "backend_priority" => ["sharp"] } }
let(:setup) { create_test_setup_with_config(custom) }
let(:config) { setup[:config] }
```

## Test Image Helpers (TestImageHelpers module)

The `TestImageHelpers` module is included in all RSpec tests and provides image validation utilities.

### `fixtures_dir`
Returns the fixtures directory path.

**Returns:** String path to `spec/fixtures/originals`

**Example:**
```ruby
let(:dir) { fixtures_dir }
```

### `test_image_path`
Returns the default test image path (cached).

**Returns:** String path to the default test image

**Example:**
```ruby
let(:image) { test_image_path }
```

### `http_test_image`
Returns a URL for HTTP-based image tests.

**Returns:** String URL (default: `"https://picsum.photos/1200/800"`)

**Example:**
```ruby
let(:url) { http_test_image }
```

### `validate_image_dimensions(image_path, expected_width, expected_height, tolerance: 2)`
Validates that an image has the expected dimensions within a tolerance.

**Parameters:**
- `image_path` - Path to the image file
- `expected_width` - Expected width in pixels
- `expected_height` - Expected height in pixels
- `:tolerance` - Allowed deviation in pixels (default: `2`)

**Returns:** Boolean

**Example:**
```ruby
expect(validate_image_dimensions(output, 800, 600)).to be true
```

### `get_image_dimensions(image_path)`
Gets actual image dimensions using `FastImage`.

**Parameters:**
- `image_path` - Path to the image file

**Returns:** Array `[width, height]` or `[nil, nil]` if failed

**Example:**
```ruby
width, height = get_image_dimensions(output_path)
```

### `validate_resize_operation(original_path, resized_path, target_width, target_height, maintain_aspect: true)`
Validates that a resize operation produced correct dimensions, optionally checking aspect ratio.

**Parameters:**
- `original_path` - Path to original image
- `resized_path` - Path to resized image
- `target_width` - Target width (or `nil` for height-only)
- `target_height` - Target height (or `nil` for width-only)
- `:maintain_aspect` - Whether aspect ratio should be maintained (default: `true`)

**Returns:** Boolean

**Example:**
```ruby
expect(validate_resize_operation(original, resized, 800, nil)).to be true
```

### `validate_crop_operation(original_path, cropped_path, expected_width, expected_height)`
Validates that a crop operation produced exact expected dimensions.

**Parameters:**
- `original_path` - Path to original image (unused but kept for API symmetry)
- `cropped_path` - Path to cropped image
- `expected_width` - Expected crop width
- `expected_height` - Expected crop height

**Returns:** Boolean

**Example:**
```ruby
expect(validate_crop_operation(original, cropped, 200, 200)).to be true
```

### `dimension_validation?(image_path, expected_width, expected_height, tolerance: 2)`
Checks dimension validation without raising (predicate-style).

**Parameters:**
- `image_path` - Path to the image file
- `expected_width` - Expected width in pixels
- `expected_height` - Expected height in pixels
- `:tolerance` - Allowed deviation in pixels (default: `2`)

**Returns:** Boolean

**Example:**
```ruby
if dimension_validation?(output, 400, 300)
  # do something
end
```

## Migration Guide

### Before (Duplicated Code):
```ruby
let(:site) { double("site", :config => TEST_CONFIG, :dest => "/tmp/test_site/_site") }
let(:config) { JekyllImgFlow::Config.new(site) }
let(:registry) { JekyllImgFlow::ProviderRegistry.new(config) }
let(:provider) { registry.current_provider }
let(:path_resolver) { JekyllImgFlow::PathResolver.new(config) }
let(:operation_processor) { JekyllImgFlow::OperationProcessor.new(provider, path_resolver) }
let(:test_image) { File.expand_path("fixtures/originals/mars-crater-large.jpg", __dir__) }
```

### After (Using Helpers):
```ruby
let(:site) { create_mock_site }
let(:components) { create_imgflow_components(site) }
let(:config) { components[:config] }
let(:operation_processor) { components[:operation_processor] }
let(:manifest) { components[:manifest] }
let(:test_image) { fixture_image_path }
```

**Lines reduced:** 8 → 5 (37% reduction)

## Benefits

- ✅ **DRY Principle** - Single source of truth
- ✅ **Consistency** - All tests use same patterns
- ✅ **Maintainability** - Change once, affects all tests
- ✅ **Readability** - Less boilerplate, clearer intent
- ✅ **Type Safety** - Documented return types
