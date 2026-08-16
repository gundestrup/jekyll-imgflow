# Jekyll ImgFlow - Architecture Documentation

## 🏗️ Overview

Jekyll ImgFlow is a modular image processing plugin for Jekyll with clear separation of responsibilities and support for multiple image processing providers.

## 📁 File Structure

```text
lib/jekyll-imgflow/
├── batch_manager.rb             # Batch job queue management
├── build_time_processor.rb      # Build-time image processing
├── config.rb                    # Configuration management
├── hooks.rb                     # Jekyll build hooks
├── imgflow_tag.rb               # {% imgflow %} tag handler
├── manifest_manager.rb          # Track image versions and page usage
├── operation_processor.rb       # Process image operations
├── parser.rb                    # Parse liquid tag markup
├── path_resolver.rb             # Centralized path resolution
├── picture_tag_adapter.rb       # {% picture %} compatibility
├── preset_manager.rb            # Manage and process presets
├── provider_registry.rb         # Manage available providers
├── tag_scanner.rb               # [OPTIONAL] Scan content for validation/reporting
├── version.rb                   # Gem version information
│
├── helpers/                     # Utility helpers
│   └── http_downloader.rb       # Download HTTP/file:// URLs
│
├── presets/                     # User presets documentation
│   ├── README.md                # Preset system documentation
│   └── examples.md              # Preset examples
│
├── providers/                   # Provider implementations
│   ├── base_provider.rb         # Base provider interface
│   ├── flyimg.rb                # Flyimg HTTP provider (alpha_opacity ✅)
│   ├── imgproxy.rb              # ImgProxy HTTP provider (alpha_opacity ✅)
│   ├── imagemagick.rb           # ImageMagick CLI provider (alpha_opacity ✅)
│   ├── libvips.rb               # LibVips CLI provider (alpha_opacity ✅)
│   └── sharp.rb                 # Sharp CLI provider (alpha_opacity ✅)
│
└── tags/                        # Individual tag files
    ├── base_tag.rb              # Shared functionality
    ├── crop_tag.rb              # Validate crop operations
    ├── format_tag.rb            # Validate format operations
    ├── opacity_tag.rb           # Validate alpha channel operations
    ├── optimize_tag.rb          # Validate optimize operations
    ├── quality_tag.rb           # Validate quality operations
    ├── resize_tag.rb            # Validate resize operations
    ├── tag_registry.rb          # Register all tags
    └── watermark_tag.rb         # Validate watermark operations

_data/imgflow/presets/           # User-defined presets (YAML)
  ├── gallery.yml
  ├── hero.yml
  └── thumbnail.yml

assets/images/                   # Source directory
  └── originals/                 # Original images

_site/assets/images/             # Built site (ephemeral, rebuilt each time)
  ├── originals/                 # Original images (copied by Jekyll)
  ├── optimized/                 # Generated images (created during build)
  └── imgflow-manifest.json      # Manifest tracking all versions
```

## 🔄 Operations Flow

### **Core Architecture: ManifestManager as Single Source of Truth**

```text
┌─────────────────────────────────────────────────────────────┐
│ ManifestManager (Single Source of Truth)                   │
│ - Tracks all image versions (default + specialized)        │
│ - Stores operations, paths, and page usage                 │
│ - Persists to _site/assets/images/imgflow-manifest.json    │
└─────────────────────────────────────────────────────────────┘
         ↑                                    ↑
         │                                    │
    BuildTimeProcessor              ImgflowTag (during rendering)
    (creates defaults)              (creates specialized)
```

### **Build-Time Processing Flow**

```text
🏗️ Jekyll Build Hook (:pre_render)
    ↓
BuildTimeProcessor.process_changed_images()
    ↓
1. Find all original images in assets/images/originals/
    ↓
2. For each original image:
   a. Build default version tasks (all sizes × all formats)
      - 4 sizes × 4 formats = 16 versions per image
   b. Add tasks to BatchManager queue
    ↓
3. BatchManager.process_all()
    ↓
4. For each task in queue:
   a. PathResolver.resolve_output_path()
      - Generates path: _site/assets/images/optimized/{name}-{size}-{hash}.{format}
   b. OperationProcessor.process_operation()
      - Calls appropriate tag (ResizeTag, etc.)
      - Tag validates parameters
      - Provider.execute() processes image
   c. ManifestManager.register_version()
      - Registers as :default version
      - Stores: operations, output path, provider
    ↓
5. ManifestManager.save()
   - Saves to _site/assets/images/imgflow-manifest.json
    ↓
6. Jekyll build continues with all default images ready in _site/
```

### **Runtime Processing Flow (ImgflowTag)**

```text
🖼️ {% imgflow image.jpg width:800 format:webp %}
    ↓
1. ImgflowTag.render()
    ↓
2. Parser.parse(markup)
   - Extracts: image path, operations
    ↓
3. FilenameGenerator.generate_filename()
   - Creates hash from operations
   - Generates: image-800-{hash}.webp
    ↓
4. ManifestManager.version_exists?(operations)
   - Checks if version already exists
   - Compares operations hash
    ↓
5a. IF EXISTS:
    - ManifestManager.update_page_usage(page_path)
    - Returns existing path
    ↓
5b. IF NOT EXISTS:
    - OperationProcessor.process_operation()
      - Creates specialized version in _site/assets/images/optimized/
    - ManifestManager.register_version()
      - Registers as :specialized version
      - Tracks page_path in used_on array
    ↓
6. PathResolver.resolve_relative_output_path()
   - Converts to relative path for HTML
    ↓
7. HtmlGenerator.generate()
   - Creates <picture> or <img> tag
   - Uses relative paths (no leading /)
    ↓
8. Returns HTML to template
```

```text
🏷️ Template Rendering: {% imgflow image.jpg width:750 quality:90 %}
    ↓
ImgflowTag.render()
    ↓
1. Parser.parse()
   - Extract: {image_path: "image.jpg", operations: [{width: 750, quality: 90}]}
    ↓
2. Tags.validate() (ResizeTag, QualityTag, etc.)
   - Validate ranges: width ✓, quality ✓ (1-100)
   - Translate symbols: :low → 60, etc.
    ↓
3. ImgflowTag.process_operations()
    ↓
4. OperationProcessor.process_operation()
   - Generate filename: "image-750w-q90.webp"
   - Check manifest: version_exists?(original_name, params, :specialized)
     - If exists: return existing path
     - If not: continue to processing
    ↓
5. Provider.execute()
   - Translate: width: 750, quality: 90 → provider commands
   - Execute: sharp -i image.jpg -o image-750w-q90.webp --resize 750 -Q 90
    ↓
6. ManifestManager.register_version()
   - Register as :specialized version
   - Track page usage: used_on: ["blog/post.html"]
    ↓
7. HtmlGenerator.generate()
   - Generate responsive <picture> or <img> HTML
   - Return HTML to template
```

### new flow manifest manager is central

```text
┌─────────────────────────────────────────────────────────────┐
│ ImgflowTag.render()                                         │
├─────────────────────────────────────────────────────────────┤
│ 1. Parse tag → operations                                   │
│ 2. FilenameGenerator.generate(original, operations) → hash  │
│ 3. ManifestManager.version_exists?(hash) ?                  │
│    ├─ YES: ManifestManager.update_page_usage(hash, page)   │
│    │        return path                                      │
│    └─ NO:  OperationProcessor.create(operations)            │
│            → ManifestManager.register_version()             │
│            return path                                       │
└─────────────────────────────────────────────────────────────┘
````

### **Picture Tag Integration Flow**

```text
🖼️ {% picture some-image.jpg %}
    ↓
PictureTagAdaptor.to_imgflow_tag()
    ↓
1. Translate Picture Tag syntax to ImgFlow syntax
   - Picture: {% picture some-image.jpg preset:gallery %}
   - ImgFlow: {% imgflow some-image.jpg preset:gallery %}
    ↓
2. Follow Runtime Processing Flow (above)
```

### **Decision Points & Caching Logic**

#### **BuildTimeProcessor.needs_processing?()**

```text
✓ Process if:
  - No versions exist in manifest
  - Original file mtime > latest version time
  - Provider changed since last processing
✗ Skip if:
  - Versions exist and are up-to-date
  - Same provider as last processing
```

#### **OperationProcessor.process_operation()**

```text
✓ Process if:
  - No manifest entry exists
  - Manifest entry exists but file doesn't exist
✗ Skip if:
  - Manifest entry exists AND file exists
  - Return existing path immediately
```

#### **Manifest Version Types**

```text
🏷️ Default Versions:
  - Generated by: BuildTimeProcessor
  - When: During Jekyll build
  - What: All sizes × all formats for each original
  - Cleanup: Never (always needed)

🎯 Specialized Versions:
  - Generated by: ImgflowTag (runtime)
  - When: When template renders with custom params
  - What: Custom operations (width:750, quality:90, crop, etc.)
  - Cleanup: If orphaned (no pages use it)
```

## 🎯 Component Responsibilities

### **ManifestManager** (Single Source of Truth)

**Role:** Central registry for all image versions and page usage

- **Tracks:** All default and specialized versions
- **Stores:** Operations, output paths, page usage, provider info
- **Methods:**
  - `version_exists?(original, operations, type)` - Check if version exists
  - `register_version(original, path, operations, type, page_path)` - Add new version
  - `update_page_usage(original, operations, page_path)` - Track page usage
  - `get_versions(original, type)` - Retrieve versions
  - `save()` - Persist to _site/assets/images/imgflow-manifest.json

### **BuildTimeProcessor**

**Role:** Create default image versions during Jekyll build

- **When:** `:pre_render` hook (after Jekyll copies assets, before rendering)
- **Creates:** Default versions (all sizes × all formats)
- **Output:** `_site/assets/images/optimized/`
- **Registers:** All versions in ManifestManager as `:default` type
- **Does NOT:** Track page usage (defaults aren't page-specific)

### **ImgflowTag**

**Role:** Handle `{% imgflow %}` tags during template rendering

- **When:** During Liquid template rendering
- **Checks:** ManifestManager for existing versions
- **Creates:** Specialized versions if not found
- **Output:** `_site/assets/images/optimized/`
- **Registers:** New versions in ManifestManager as `:specialized` type
- **Tracks:** Page usage via `update_page_usage()`
- **Returns:** HTML with relative image paths

### **OperationProcessor**

**Role:** Execute image processing operations

- **Called by:** BuildTimeProcessor and ImgflowTag
- **Does:**
  - Validates operations via tag classes (ResizeTag, etc.)
  - Calls provider to process image
  - Returns output path
- **Does NOT:**
  - Check manifest (caller's responsibility)
  - Register versions (caller's responsibility)

### **BatchManager**

**Role:** Queue and process multiple image operations

- **Used by:** BuildTimeProcessor only
- **Does:**
  - Queue tasks for parallel processing
  - Call OperationProcessor for each task
  - Track completed/failed tasks
- **Returns:** Results for BuildTimeProcessor to register in manifest

### **PathResolver**

**Role:** Centralized path management

- **Methods:**
  - `resolve_output_path(filename)` - Full path to _site/assets/images/optimized/
  - `resolve_relative_output_path(filename)` - Relative path for HTML/manifest
  - `resolve_original_path(image_name)` - Path to original image
- **Ensures:** Consistent path handling across all components

### **FilenameGenerator**

**Role:** Generate deterministic filenames from operations

- **Format:** `{original}-{size}-{hash}.{format}`
- **Hash:** MD5 of sorted operations (ensures same operations = same filename)
- **Used by:** All components that create images

### **TagScanner** (Optional - Not in Core Flow)

**Role:** Pre-build analysis and validation

- **Status:** Optional tooling, not part of core processing
- **Potential uses:**
  - Pre-build validation of image references
  - Generate usage reports
  - Detect dead/unused images
- **Does NOT:**
  - Track versions (ManifestManager does this)
  - Participate in image processing flow

### **Error Handling & Recovery**

```text
🔄 BatchManager.retry_failed()
   - Collect failed tasks
   - Retry with exponential backoff
   - Report final statistics

⚠️ Provider Fallback:
   - ProviderRegistry.next_available()
   - Continue with next provider
   - Log provider-specific errors

🚨 Tag Errors:
   - Try/Catch in ImgflowTag
   - Return error HTML comment
   - Continue page rendering
```

### **Performance Optimizations**

```text
🚀 Build Time:
  - BatchManager: Queue multiple images
  - Parallel processing: Multiple providers
  - Manifest caching: Avoid re-processing

⚡ Runtime:
  - Manifest lookup: O(1) hash lookup
  - File existence check: Quick OS check
  - Immediate return: No processing if cached

🧹 Cleanup:
  - Orphan detection: Scan manifest.used_on arrays
  - Selective cleanup: Only specialized versions
  - Preserve defaults: Always keep default versions
```

## 🎯 Separation of Responsibilities

### **1. Parser** (`parser.rb`)

**Responsibility:** Parse liquid tag markup into structured data

**Does:**

- Extract image path from markup
- Extract operation parameters (key:value pairs)
- Extract HTML attributes
- Return structured hash

**Does NOT:**

- Validate parameter values
- Execute operations
- Know about providers

### **2. Tags** (`tags/*.rb`)

**Responsibility:** Validate operation parameters

**Does:**

- Validate parameter ranges (e.g., quality 1-100)
- Validate required parameters
- Translate symbolic values (e.g., :low → 60)
- Return validated data

**Does NOT:**

- Parse markup
- Execute operations
- Know about provider implementation

#### **Quality vs Optimize Tags:**

**Quality Tag:** Direct quality number (1-100) for precise control.
**Optimize Tag:** User-friendly levels (`:low`, `:medium`, `:high`, `:maximum`) that translate to quality values.

*OptimizeTag is a wrapper around QualityTag - both call the same provider method.*

#### **Opacity Tag:**

**Opacity Tag:** Alpha channel manipulation (0.01-0.99) for transparency effects.

- **Requires explicit opacity value** (no default - enforced by Parser)
- **Validates range:** 0.01 (nearly transparent) to 0.99 (nearly opaque)
- **Provider translation:** Converts to provider-specific alpha channel formats

*OpacityTag manipulates the image's alpha channel directly, separate from watermark opacity.*

### **3. Providers** (`providers/*.rb`)

**Responsibility:** Translate operations to provider-specific API

**Does:**

- Translate 1-100 quality to provider format
- Translate 0.01-0.99 opacity to provider format
- Build CLI commands or HTTP URLs
- Execute provider calls
- Return processed image path
- Handle unsupported operations gracefully

**Does NOT:**

- Validate input parameters
- Parse markup
- Know about Jekyll

#### **Alpha Opacity Support:**

- **✅ CLI Providers** (Sharp, ImageMagick, LibVips): Direct alpha channel manipulation
- **✅ HTTP API Providers** (Imgproxy, Weserv, Flyimg): URL parameter translation

#### **Provider Translation Examples:**

```text
Opacity 0.5 → Sharp: --alpha {alpha:128}
Opacity 0.5 → ImageMagick: -alpha set -channel A -evaluate multiply 50%
Opacity 0.5 → LibVips: multiply [0.5]
Opacity 0.5 → Imgproxy: a:128
Opacity 0.5 → Weserv: alpha=0.5
Opacity 0.5 → Flyimg: a_50
```

### **4. ManifestManager** (`manifest_manager.rb`)

**Responsibility:** Track image versions and page usage

**Does:**

- Track default vs specialized versions
- Track which pages use which versions
- Detect orphaned images
- Cleanup unused images
- Store manifest in `_site/` (auto-reset on rebuild)

**Does NOT:**

- Generate images
- Validate operations
- Know about providers

### **5. TagScanner** (`tag_scanner.rb`)

**Responsibility:** Scan content for image requirements

**Does:**

- Scan posts, pages, documents for `{% imgflow %}` tags
- Identify default vs specialized versions
- Build list of required images
- Track page usage

**Does NOT:**

- Generate images
- Validate parameters
- Execute operations

### **6. Config** (`config.rb`)

**Responsibility:** Manage configuration

**Does:**

- Load defaults
- Merge `_config.yml` overrides
- Provide config access
- Handle fallback values

**Does NOT:**

- Process images
- Validate operations
- Know about providers

### **7. PathResolver** (`path_resolver.rb`)

**Responsibility:** Centralized path management

**Does:**

- Resolve original image paths
- Generate output paths with operation markers
- Create temporary file paths
- Build public URLs
- Convert between absolute and relative paths

**Does NOT:**

- Process images
- Validate operations
- Download files

### **8. HttpDownloader** (`helpers/http_downloader.rb`)

**Responsibility:** Download remote images

**Does:**

- Download HTTP/HTTPS URLs to temp files
- Handle file:// URLs (copy to temp)
- Follow HTTP redirects
- Handle download errors

**Does NOT:**

- Process images
- Know about providers
- Manage paths (uses PathResolver)

### **9. OperationProcessor** (`operation_processor.rb`)

**Responsibility:** Process image operations using providers

**Does:**

- Process single operations (resize, crop, quality, alpha_opacity, etc.)
- Process batch operations (chain multiple operations)
- Validate operations using tag classes
- Check if processing is needed (cache check)
- Build operations array from tag parameters

**Does NOT:**

- Manage job queue (BatchManager does this)
- Register in manifest (BuildTimeProcessor does this)
- Parse markup
- Know about Jekyll

**Key Methods:**

```ruby
process_single_operation(type, input, output, params)
process_batch_operations(operations, input, output)
process_operation(original, type, input, output, params)
needs_processing?(input, output, operations)
build_operations_from_params(tag_params)
```

### **10. BatchManager** (`batch_manager.rb`)

**Responsibility:** Manage batch processing of image operations

**Does:**

- Queue tasks for processing
- Process tasks sequentially or in parallel
- Track completed and failed tasks
- Retry failed tasks
- Build task definitions for default/specialized versions
- Provide status and statistics

**Does NOT:**

- Process images directly (OperationProcessor does this)
- Validate operations
- Know about providers

**Key Methods:**

```ruby
add_task(task)
add_tasks(tasks)
process_all(parallel: false)
status()
retry_failed()
BatchManager.build_default_tasks(original, input, config)
BatchManager.build_specialized_task(original, input, ops, output, page)
```

**Task Structure:**

```ruby
{
  original_name: "image.jpg",
  operation_type: :resize,
  input_path: "originals/image.jpg",
  output_path: "optimized/image-800w.webp",
  params: { width: 800, format: "webp", quality: 85 },
  version_type: :default,  # or :specialized
  page_path: "blog/post.html",
  skip_if_exists: true
}
```

### **11. PresetManager** (`preset_manager.rb`)

**Responsibility:** Manage and process image presets

**Does:**

- Load presets from `_data/imgflow/presets/*.yml`
- Get preset by name
- Build operations from preset definition
- Apply preset to images
- List available presets

**Does NOT:**

- Process images directly (OperationProcessor does this)
- Validate operations
- Parse liquid tags

**Key Methods:**

```ruby
get_preset(name)
preset_exists?(name)
available_presets()
build_operations_from_preset(preset_name)
apply_preset(preset_name, input, output, operation_processor)
```

### **12. BuildTimeProcessor** (`build_time_processor.rb`)

**Responsibility:** Process images during Jekyll build

**Does:**

- Find all original images
- Check if images need processing
- Build default version tasks
- Use BatchManager to process all tasks
- Register completed operations in manifest
- Save manifest after processing
- Integrate with Jekyll hooks

**Does NOT:**

- Process specialized versions (runtime only)
- Parse liquid tags
- Know about individual providers

**Key Methods:**

```ruby
process_changed_images()
```

**Used By:**

- Jekyll hooks (`:post_read`)
- Development and production builds

### **13. Version** (`version.rb`)

**Responsibility:** Provide gem version information

**Does:**

- Define current version number
- Used by gem management and updates

**Does NOT:**

- Process images
- Handle configuration

### **14. Presets Directory** (`presets/`)

**Responsibility:** User preset documentation and examples

**Contains:**

- `README.md` - Preset system documentation
- `examples.md` - Preset examples and templates

**Does:**

- Document preset format (YAML)
- Provide usage examples
- Explain preset creation process

**Does NOT:**

- Load presets (PresetManager does this)
- Process images

## 🔄 Image Version Types

### **Default Versions**

Generated automatically for all images in originals folder.

**Defined by:**

- `config.sizes` (e.g., sm: 400, md: 800, lg: 1200)
- `config.formats` (e.g., avif, webp, png, jpg)
- `config.quality` (default: 85)

**Example:**

```text
image.jpg →
  - image-400w.webp (default)
  - image-800w.webp (default)
  - image-1200w.webp (default)
  - image-400w.avif (default)
  - image-800w.avif (default)
  - image-1200w.avif (default)
```

### **Specialized Versions**

Generated on-demand when tags specify custom operations.

**Triggered by:**

- Custom width/height not in config.sizes
- Custom quality not matching default
- Custom operations (crop, watermark, etc.)

**Example:**

```liquid
{% imgflow image.jpg width:750 quality:90 %}
```

Generates: `image-750w-q90.webp` (specialized)

## 📊 Manifest Structure

Located at: `_site/assets/images/imgflow-manifest.json`

```json
{
  "image.jpg": {
    "versions": {
      "default": [
        {
          "output": "optimized/image-400w.webp",
          "operations": {"width": 400, "format": "webp"},
          "type": "default",
          "used_on": ["index.html", "about.html"],
          "created_at": 1234567890
        }
      ],
      "specialized": [
        {
          "output": "optimized/image-750w-q90.webp",
          "operations": {"width": 750, "quality": 90, "format": "webp"},
          "type": "specialized",
          "used_on": ["blog/post1.html"],
          "created_at": 1234567900
        }
      ]
    }
  }
}
```

## 🔧 Processing Flow

### **Development Mode:**

```text
1. User adds image to assets/images/originals/
   ↓
2. Build-time processor detects new file
   ↓
3. VariantGenerator creates default versions
   ↓
4. ManifestManager tracks versions
   ↓
5. Images ready for use
```

### **Tag Usage:**

```text
1. User writes {% imgflow image.jpg width:750 quality:90 %}
   ↓
2. Parser extracts: {image: "image.jpg", ops: {width: 750, quality: 90}}
   ↓
3. Tags validate: width ✓, quality ✓ (1-100)
   ↓
4. ManifestManager checks if version exists
   ↓
5. If not exists:
   - Create task with validated operations
   - Provider translates & executes
   - ManifestManager registers version
   ↓
6. Return HTML with image URL
```

### **OpacityTag Usage:**

```text
1. User writes {% imgflow logo.png opacity:0.3 %}
   ↓
2. Parser extracts: {image: "logo.png", ops: {opacity: 0.3}}
   ↓
3. Parser validates: opacity ✓ (0.01-0.99, required)
   ↓
4. OpacityTag processes: alpha channel manipulation
   ↓
5. Provider translates: 0.3 → provider-specific format
   ↓
6. Return HTML with transparent image URL
```

### **Build/Deploy:**

```text
1. TagScanner scans all content
   ↓
2. Build manifest of required images
   ↓
3. Generate missing specialized versions
   ↓
4. Cleanup orphaned specialized images
   ↓
5. Jekyll build completes
   ↓
6. Deploy _site/ (all images pre-generated)
```

## 🧹 Orphan Cleanup

**Orphaned Image:** A specialized version no longer used on any page.

**Detection:**

- ManifestManager tracks `used_on` array for each version
- When page is deleted, remove from `used_on`
- If `used_on` is empty, image is orphaned

**Cleanup:**

- Default versions: Never cleaned (always needed)
- Specialized versions: Cleaned if orphaned
- Run cleanup on build or manually

## 🎨 Presets

**Location:** `_data/imgflow/presets/*.yml`

**Format (YAML):**

```yaml
# _data/imgflow/presets/thumbnail.yml
name: thumbnail
description: Small thumbnail images

operations:
  - resize:
      width: 200
      height: 200
  - quality: 80
  - formats: [webp, jpg]
```

**Usage:**

```liquid
{% imgflow image.jpg preset:thumbnail %}
```

**Generate Preset Template:**

```bash
rake imgflow:preset[my_preset]
```

## 🔌 Provider System

### **Provider Interface:**

```ruby
class MyProvider < BaseProvider
  def available?
    # Check if provider is available
  end

  def execute(input_path, output_path)
    # Process queued operations
  end

  private

  def translate_quality_to_my_provider(quality)
    # Translate 1-100 to provider format
  end
end
```

### **Adding New Provider:**

1. Create `lib/jekyll-imgflow/providers/my_provider.rb`
2. Inherit from `BaseProvider`
3. Implement `available?` and `execute`
4. Add translation methods for operations
5. Register in `provider_registry.rb`

## 📝 Configuration

**Default values:** `lib/jekyll-imgflow/config.rb`

**User overrides:** `_config.yml`

```yaml
# _config.yml
imgflow:
  originals: "assets/images/originals"
  output: "assets/images/optimized"
  quality: 85
  sizes:
    sm: 400
    md: 800
    lg: 1200
  formats:
    - avif
    - webp
    - png
    - jpg
  backend_priority:
    - sharp
    - libvips
    - imagemagick
```

## ✅ Best Practices

1. **Validation upstream, translation downstream**
   - Tags validate (1-100)
   - Providers translate (1-100 → provider format)

2. **Single Responsibility**
   - Each file has one clear purpose
   - No overlapping responsibilities

3. **Config-driven defaults**
   - No hardcoded values
   - All defaults in config.rb
   - User overrides in _config.yml

4. **Manifest in _site/**
   - Auto-reset on rebuild
   - Tracks all versions
   - Enables smart cleanup

5. **Default vs Specialized**
   - Default: Always generated, never cleaned
   - Specialized: On-demand, cleaned if orphaned

## 💡 Usage Examples

### **Example 1: Processing Default Versions**

```ruby
# Initialize components
config = JekyllImgFlow::Config.new(site)
manifest = JekyllImgFlow::ManifestManager.new(site)
path_resolver = JekyllImgFlow::PathResolver.new(config)
provider = registry.best_provider
op_processor = JekyllImgFlow::OperationProcessor.new(provider, path_resolver)
batch_manager = JekyllImgFlow::BatchManager.new(op_processor)

# Build tasks for default versions
tasks = JekyllImgFlow::BatchManager.build_default_tasks(
  "image.jpg",
  "originals/image.jpg",
  config
)

# Add to batch queue
batch_manager.add_tasks(tasks)

# Process all
results = batch_manager.process_all
# => { total: 9, completed: 9, failed: 0, duration: 2.5 }
```

### **Example 2: Processing Specialized Version**

```ruby
# Build specialized task
task = JekyllImgFlow::BatchManager.build_specialized_task(
  "image.jpg",
  "originals/image.jpg",
  [{ type: :resize, params: { width: 750, quality: 90 } }],
  "optimized/image-750w-q90.webp",
  "blog/post.html"
)

# Add and process
batch_manager.add_task(task)
batch_manager.process_all
```

### **Example 3: Batch Operations (Chained)**

```ruby
# Chain multiple operations
operations = [
  { type: :resize, params: { width: 800 } },
  { type: :crop, params: { ratio: "16:9" } },
  { type: :quality, params: { quality: 90 } },
  { type: :alpha_opacity, params: { opacity: 0.5 } },
  { type: :watermark, params: { watermark: "logo.png", opacity: 0.7 } }
]

# Process as batch (more efficient than separate operations)
result = op_processor.process_batch_operations(
  operations,
  "originals/image.jpg",
  "optimized/image-final.jpg"
)
```

### **Example 4: Check and Skip Processing**

```ruby
# Check if processing needed
if op_processor.needs_processing?(input_path, output_path, operations)
  # Process only if needed
  op_processor.process_single_operation(:resize, input_path, output_path, params)
else
  # Skip - already up-to-date
  puts "Skipping - already processed"
end
```

### **Example 5: Retry Failed Tasks**

```ruby
# Process batch
batch_manager.process_all

# Check status
status = batch_manager.status
# => { queued: 0, completed: 8, failed: 1, total: 9 }

# Retry failed
retried = batch_manager.retry_failed
# => 1

# Process again
batch_manager.process_all
```

## 🚀 Future Enhancements

- [x] PathResolver for centralized path management ✅
- [x] OperationProcessor for batch processing ✅
- [x] BatchManager for job queue optimization ✅
- [x] OpacityTag for alpha channel manipulation ✅
- [ ] FileWatcher for real-time monitoring
- [ ] PictureTagAdapter for jekyll-picture-tag compatibility
- [ ] Rake tasks for preset generation
- [ ] Performance metrics and logging
- [ ] Parallel processing in BatchManager
- [ ] Progress callbacks and events
