# Changelog


## [Unreleased]

### Fixed
- **Parallel test race condition in temp file cleanup** — `cleanup_temp_output_files` in `spec_helper.rb` deleted ALL `imgflow-out-*` files in `Dir.tmpdir` with no age check. In parallel mode, process 0's pre-suite cleanup could delete temp files being actively used by other processes, causing sharp to fail with "No input files". Fixed by only deleting files older than 1 hour.
- **Parallel test race condition in temp file counting test** — `operation_processor_spec.rb` "cleans up temporary files" test compared global `imgflow-out-*` counts before/after processing. In parallel mode, other processes create/delete temp files between snapshots, causing false failures. Fixed by stubbing `PathResolver#temp_output_path` with a test-specific prefix so only this test's temp files are counted.


## [0.1.7] - 2026-08-16

### Added
- **Minimal config support** — users only need to specify `originals` and `output` in `_config.yml`. All other settings (`quality`, `formats`, `sizes`, `backend_priority`, `input_formats`) now have sensible defaults built into the `Config` class. An empty `imgflow:` block works out of the box.
- **`fallback_format` config option** — controls which format is used for the `<img>` fallback in `<picture>` elements (default: `jpg`). All other formats get `<source>` tags for browsers that support them.
- **End-to-end regression test** (`spec/realworld_build_spec.rb`) — builds a real Jekyll site with the plugin, runs `jekyll build` twice, and verifies optimized images survive in `_site/` across rebuilds. Uses 12 real-world fixture images (6 JPG, 6 GIF including 1 animated). Tagged `:slow`.
- **Format priority ordering** — `<source>` tags in `<picture>` elements are now emitted in config format priority order (avif → webp → png → jpg), so the browser picks the best format it supports.
- Documentation for image referencing limitations (no fuzzy matching/autocomplete yet).

### Changed
- **`DEFAULT_FORMATS` reordered** from `[webp, avif, jpg, png]` to `[avif, webp, png, jpg]` — AVIF is served first (best compression), WebP as fallback for AVIF, PNG for transparency, JPG as universal `<img>` fallback.
- **`DEFAULT_BACKEND_PRIORITY` reordered** by benchmark speed: `sharp` (14s) → `libvips` (22s) → `imagemagick` (31s) → `imgproxy` (31s) → `weserv` (30s) → `flyimg`. Previous order had `imgproxy` second despite being slower.
- **Removed required-field validation** from `Config#initialize` — `originals`, `output`, `input_formats`, `formats`, and `sizes` now fall back to defaults instead of raising `ArgumentError`.
- **Fixed `HtmlGenerator` fallback logic** — previously all configured formats were treated as "fallback formats", causing all `<source>` tags to be skipped. Only the configured `fallback_format` is now skipped in the `<source>` loop.
- Updated `benchmark` gem 0.4.1 → 0.5.0 and `rubocop-performance` 1.26.1 → 1.27.0.
- Updated README.md, docs/installation.md, docs/ARCHITECTURE.md, docs/usage/tags.md with new config format, defaults table, and format priority documentation.
- Removed 113 unused test fixture images (9.6 MB → 352 KB), keeping only the 12 used by the regression test.

### Fixed
- **Optimized images wiped from `_site` on rebuild (v0.1.6 bug)** — images were written directly to `_site/` which Jekyll clears at the start of each build. Fixed by writing to the source directory and registering generated files as `Jekyll::StaticFile` objects during the `pre_render` hook, so Jekyll copies them to `_site` during its write phase. This works on the first build (previously required two builds).
- **`keep_files: ["assets"]` removed from spec_helper.rb** — this setting masked the v0.1.6 wipe bug by preventing Jekyll from cleaning `_site/assets/` between builds. All 1064 tests pass without it.
- **Manifest path storage** — manifest now stores relative paths with leading slash (`/assets/images/optimized/...`) for consistency with Jekyll conventions.

### Improved
- Test suite expanded from 1052 to 1064 examples with 0 failures.
- Line coverage: 97.97%.
- RuboCop: 0 offenses across all files.
- `AI_INSTRUCTIONS.md` updated with test infrastructure lessons documenting why the v0.1.6 bug went undetected.


## [0.1.6] - 2026-08-15

### Added
- `AnimatedGifDetector` — pure-Ruby GIF frame counter that detects animated GIFs (multiple Image Descriptor blocks) without any new gem dependencies. Supports both GIF87a and GIF89a.
- Animated GIFs are now preserved as-is during image processing: `OperationProcessor` copies the original file byte-for-byte instead of resizing or format-converting, which would destroy the animation. A warning is logged so users know the image was skipped.
- `BuildTimeProcessor` now filters out animated GIFs early in `find_original_images`, so no default versions are queued for them — avoiding unnecessary work and manifest clutter.
- Test fixtures for animated GIF (`ang-head-animation.gif`) and static single-frame GIF (`static-single-frame.gif`).
- Test coverage for the animated GIF detection and skip behavior (11 new examples).

### Fixed
- Animated GIFs were being resized and format-converted, destroying their animation. They are now copied unchanged to the output path while still being tracked in the manifest.
- Security: updated `json` gem 2.21.1 → 2.21.2 to fix CVE-2026-71847 (crash on truncated duplicate-key streams).
- Fixed gemspec version mismatch (was still 0.1.5 after bump).
- Fixed SimpleCov deprecation warning (`add_filter` → `skip`) and removed duplicate `SimpleCov.start` call.

### Changed
- **Minimum Ruby version bumped from 3.3.0 to 3.4.0.** Tested with Ruby 3.4.10.
- Updated `.ruby-version` to 3.4.10, `TargetRubyVersion` in `.rubocop.yml` to 3.4, CI matrix to test Ruby 3.4 only.
- Added `ostruct` and `benchmark` gems to Gemfile to silence Ruby 4.0 stdlib removal warnings.
- Updated gemspec dev dependency versions to match pinned Gemfile versions.

### Improved
- Test suite expanded from 1005 to 1052 examples with 0 failures.
- Line coverage increased to 98.23%.
- RuboCop: fixed all 19 pre-existing offenses (global variables in `spec_helper.rb`, identical conditional branches in `imgproxy.rb`, `receive_messages` consolidation in test specs). RuboCop now passes with 0 offenses across all 102 files.
- Pinned all Gemfile dependencies to the newest verified working versions (e.g., `jekyll ~> 4.4.1`, `rubocop ~> 1.89.0`, `simplecov ~> 1.1.1`).
- Updated transitive dependencies: `csv` 3.3.5 → 3.3.6, `erb` 6.0.6 → 6.0.7, `sass-embedded` 1.101.6 → 1.102.0, `zeitwerk` 2.8.2 → 2.8.3, `rbs` 4.0.3 → 4.1.3, `dry-configurable` 1.3.0 → 1.4.0, `reline` 0.6.3 → 0.7.0, `io-console` 0.8.2 → 0.9.2.
- Remaining outdated gems (`liquid`, `rouge`, `terminal-table`, `objective_elements`, `diff-lcs`, `unicode-display_width`) are blocked by Jekyll 4.x dependency constraints and cannot be updated until Jekyll 5.x.


## [0.1.5] - 2026-07-28

### Added
- Unique millisecond-precision and random-suffixed temporary directories for provider and test helper output, eliminating flaky filesystem collisions.
- Explicit format-continuity inference to imgproxy, weserv, and flyimg provider URLs so chained operations preserve output formats.

### Changed
- `provider_implementation_coverage_spec.rb` now builds `all_providers` from the full provider registry instead of `backend_priority`, so installed CLI tools (Sharp, ImageMagick, Libvips) are tested even when an HTTP provider is selected.
- Tightened provider URL generation for resize, crop, and smartcrop operations across imgproxy, weserv, and flyimg.

### Fixed
- imgproxy resize now allows upscaling (`enlarge=1`) and preserves exact-fill dimensions.
- weserv source URL is now correctly URL-encoded and exact-fill resize is forced with `fit=fill`.
- weserv Docker test container SSRF policy and DNS resolver relaxed so `host.docker.internal` is reachable.
- flyimg crop and smartcrop parameter formats now match the Flyimg API (`e_1`, `p1x_...`, `p2x_...`, `smc_1`).
- flyimg `pns_1` default blocking upscaling is now overridden with `pns_0` for resize operations.
- flyimg shared memory allocation increased to `1gb` to avoid ImageMagick out-of-memory failures.
- Provider test suite now passes with 0 failures for default CLI, imgproxy, weserv, and flyimg configurations.

### Improved
- Overall test reliability and code-coverage reporting (line coverage ~95-96%).

## [0.1.1] - 2026-03-12

### Added
- Comprehensive testing and quality assurance framework
- Automated release scripts with validation
- RuboCop code style checking
- Reek code smell detection  
- Bundler audit security scanning
- RSpec test framework with coverage reporting
- Version bumping automation
- CHANGELOG template generation 

### Changed
- Improved code style with 128+ auto-corrections
- Standardized project structure and configuration
- Enhanced development workflow with quality gates 

### Fixed
- Test framework setup and module loading issues
- Version file path configuration in release scripts
- RSpec configuration and test dependencies 

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
