# Changelog

## [0.4.0] - 2026-09-12

### Changed

- Extracted shared provider behavior into `BaseProvider` helpers
  (`find_op`, `op?`, `crop_geometry`, `watermark_parts`, `compass_to_short`,
  `input_format_ext`) to eliminate duplicated operation lookups, crop
  parsing, watermark extraction, and compass-position translation across all
  six providers.
- Introduced `Providers::HttpBase < BaseProvider` to centralize HTTP-provider
  availability checks, request execution, fetching with timeout, and error
  handling. `imgproxy`, `weserv`, and `flyimg` now inherit this scaffolding
  and only provide their service URL and URL-building logic.
- Introduced `Providers::CliBase < BaseProvider` to centralize the shared
  CLI-provider `execute` skeleton (empty-operations guard, build, run,
  reset). `sharp`, `imagemagick`, and `libvips` now inherit it and only
  provide `build_commands` and optional `before_execute`/`run_command`
  overrides.
- Added `cli_available?(*commands)`, `temp_path(input_path, suffix)`,
  `alpha_byte_value(opacity)`, and `smartcrop_interestingness(keep)`
  helpers to `BaseProvider`, eliminating repeated `Open3.capture3("which",
  …)` calls, temp-file path `gsub` patterns, `* 255).round` calculations,
  and smartcrop interestingness mappings across all six providers.
- Moved duplicated `validate_quality`, `valid_numeric?`, and
  `validate_opacity` methods from individual tag classes into `BaseTag`.
  `validate_opacity` is now parameterized by `min:`/`max:` so both
  `OpacityTag` (0.01–0.99) and `WatermarkTag` (0.0–1.0) share one
  implementation.
- Consolidated `CropTag#get_original_dimensions` into `BaseTag` as a
  raising variant of the existing `get_image_dimensions` helper.
- Refactored `sharp`, `imagemagick`, and `libvips` to use the shared
  `crop_geometry`, `watermark_parts`, and `op?` helpers, removing the
  repeated crop-parsing block and operation lookups.
- Removed no-op `translate_quality_to_*` methods from the HTTP providers;
  they returned the input quality unchanged.
- Decomposed `Parser.detect_operations`, `PresetManager.yaml_to_tags`,
  `TagScanner#parse_tag_markup_simple`, `PictureTagPresetMigrator`
  conversion/description, `CropTag#process`, and `ResizeTag#process` into
  smaller focused helper methods without changing behavior.

### Fixed

- Weserv provider now handles SVG files without explicit pixel dimensions
  (e.g. `width="100%"` with a large `viewBox`). When no resize or crop
  operation is present, a default `w=2000` parameter is added so librsvg
  rasterizes at a reasonable size instead of the full viewBox dimensions
  (which could exceed 85 megapixels and cause memory exhaustion or
  connection drops).
- Removed the duplicate `show_status` definition in `scripts/test_logger.rb`
  that shadowed the canonical implementation in `class << self`.

## [0.3.3] - 2026-09-11

### Added

- Added Semgrep and CodeFactor status badges to the README.
- Documented local Semgrep Pro scans and `semgrep ci` dashboard
  synchronization. GitHub Actions continues to publish CI findings through
  `SEMGREP_APP_TOKEN`, while CodeFactor analyzes the repository through its
  GitHub integration.

### Fixed

- Replaced shell-interpolated cleanup and test-helper commands with argument
  arrays and process APIs where possible.
- Added explicit Semgrep suppressions for intentional Jekyll Picture Tag MD5
  compatibility hashes and provider commands that use safe argument arrays or
  shell-escaped paths.
- Refactored complex test helpers, performance-report helpers, configuration,
  Picture Tag translation, manifest registration, provider pipelines, and
  ImgFlow operation processing without changing behavior.
- Corrected chained collection-method alignment and shell argument display in
  test utilities.
- Prevented unchanged rebuilds from persisting the transient manifest state
  created while specialized page usage is reset, keeping the final manifest
  timestamp stable when its content is unchanged.
- Increased the Flyimg request timeout for large PNG/TIFF processing and
  reduced default slow-test concurrency to avoid exhausting local Docker
  resources during comprehensive provider runs.

### Changed

- Updated the checked-in performance benchmark report and JSON results from the
  full local provider test run.

### Security

- Pinned all GitHub Actions used by CI and release workflows to immutable
  commit SHAs to prevent mutable-tag supply-chain changes.

## [0.3.2] - 2026-09-09

### Fixed

- **Modal full-size variants** — modal links now generate optimized variants at
  the smaller of the original image width and configured maximum size, avoiding
  upscaled 2000px outputs for originals such as 1680px images.
- **Modal format negotiation** — the modal now opens a `<picture>` element with
  AVIF/WebP/PNG sources and the configured fallback format, instead of always
  loading the fallback file directly.

### Added

- Regression coverage for original-width modal generation and optimized modal
  format selection.

## [0.3.1] - 2026-09-09

### Fixed

- **Sharp CLI format compatibility** — the Sharp provider now translates
  ImgFlow's public `jpg` format name to Sharp CLI's required `jpeg` argument,
  preserving `.jpg` output filenames while supporting Sharp CLI 6.x.

### Changed

- Development and CI tooling now pins Sharp CLI to `6.1.0`, with Dependabot
  coverage for the npm development dependency tree.
- CI and local development now share the committed Ruby version from
  `.ruby-version`; `rake ci` mirrors the GitHub Actions checks and runs
  automatically from the pre-push hook.
- CI uses Ubuntu 26.04 with the required libvips/ImageMagick and AVIF codec
  packages, while Docker-backed HTTP provider tests remain local-only.

### Security

- Fixed incomplete escaping of backslashes in preset image paths.
- Replaced the Picture Tag adaptor's backtracking regex with indexed parsing to
  remove the CodeQL polynomial-ReDoS finding.

## [0.3.0] - 2026-09-09

### Added

- **Image modal/lightbox by default** — clicking an `{% imgflow %}` image now opens a full-size modal popup showing the largest generated version. The modal is enabled by default (`image_modal: true` in config) and requires no user setup — CSS and JS are automatically injected into pages that contain modal-enabled images via a `post_render` hook. Disable globally in `_config.yml` with `image_modal: false`. Per-image overrides: `modal:true` forces the modal on (even when config is `false`), `modal:false` forces it off. Images with an explicit `link:` attribute use that link instead (modal is skipped). The modal supports keyboard navigation (Escape to close) and click-outside-to-close.

## [0.2.0] - 2026-09-08

### Fixed

- **Specialized and default versions only produced a single format** — `{% imgflow %}` tags without an explicit `format:`/`formats:` parameter generated only one output file (falling back to the original extension, e.g. `.jpg`) and rendered a simple `<img>` tag instead of a `<picture>` element. `process_variants` now expands to all configured formats (`avif`, `webp`, `png`, `jpg`) when no format is specified, so both default-width and specialized versions produce a `<picture>` with `<source>` tags for modern formats and an `<img>` fallback. Explicit `format:` and `formats:` selections (e.g. `format:avif`, `formats:avif,png`, `formats:webp,jpg`) are respected for both default and specialized widths.

### Added

- Unit and integration tests verifying explicit format selection: single format (`format:avif`), multiple formats (`formats:avif,png`, `formats:webp,jpg`), and no-format expansion for both default and specialized widths.
- Tests verifying format config change lifecycle: obsolete default format files are deleted when formats shrink (e.g. `avif,webp,png,jpg` → `avif,png`), missing formats are detected for regeneration when formats grow (e.g. `avif,png` → `avif,png,jpg`), and specialized versions are preserved during default cleanup.

## [0.1.11] - 2026-09-07

### Added

- Rake task `check_docker_images` queries upstream registries (GHCR, Docker Hub) for the latest version tags and compares against the pins in `docker-compose.base.yml`. Use `STRICT=true` to fail the task when any pin is outdated — run before releasing.
- Rake tasks `start_services` and `stop_services` for starting and stopping test Docker services. `start_services` pulls the latest pinned images before starting containers.
- Pre-push git hook now runs `check_docker_images` when pushing a `v*` tag, blocking releases with stale Docker image pins.
- Release workflow (`release.yml`) now verifies Docker image pins are current before building and publishing the gem.
- Rake tasks `imgflow:presets` and `imgflow:install_presets` for listing and installing built-in YAML presets in consuming sites that load `jekyll-imgflow/tasks` from their Rakefile.
- Built-in YAML presets `gallery`, `hero`, and `thumbnail` shipped under `lib/jekyll-imgflow/presets/`; user presets in `_data/imgflow/presets/*.yml` override built-ins.
- `{% imgflow ... preset:NAME %}` tags now expand YAML presets through `PresetManager`, with user tag values overriding preset values and multi-format presets rendering `<picture>` sources plus a fallback image.
- Rake task `parallel:slow` runs slow tests in parallel using a dynamic work queue across providers, cross-provider comparisons, manifest changes, error handling, and performance benchmarks, utilizing available CPU cores.
- `TestEnvironment` module (`spec/support/test_environment.rb`) centralizes provider lists, port allocation, and test configuration previously inlined in `spec_helper.rb`, eliminating duplicated constants and port-collision bugs in parallel test runs.
- `spec/support/provider_integration_helper.rb` extracted shared provider integration test setup (prebuilt sites, server lifecycle, fixture selection) from `spec_helper.rb`.
- `spec/docker_service_status_spec.rb` adds 23 unit tests for `DockerServiceStatus` covering service path mapping, readiness/failed state detection, compose record parsing (single/array/newline-delimited/invalid JSON), HTTP status (200/503/connection refused/EOF/timeout), container status, and wait/timeout behavior.

### Fixed

- **Manifest wiped on every server restart** — the manifest now persists under the configured `cache_dir` instead of `_site/`, so Jekyll destination cleanup cannot remove it. The cache directory is excluded from Jekyll watch processing, unchanged manifests are not rewritten, and updates use an atomic temporary-file rename.
- **Persisted operation comparison** — manifest operations are recursively normalized after JSON persistence, preventing duplicate versions when in-memory symbol keys or values are compared with persisted strings.
- **Unwritten `.cache_key` dependency** — cache checks no longer require sidecar files that no code path created. Every generated version stores the SHA-256 digest of its source bytes, so changed content is regenerated even when `mtime` is preserved, while timestamp-only changes remain cached.
- **Incomplete cache checks** — every configured default size/format/quality combination must have a matching manifest entry, current provider, current source digest, and existing output file before an original is skipped. Missing default or specialized outputs and newly configured defaults are regenerated.
- **Stale generated files** — deleted originals now remove their default and specialized outputs from both source and destination. Defaults removed from configured sizes/formats are pruned with path-safe deletion and empty-directory cleanup.
- **Deleted-original matching** — cleanup compares complete paths relative to the originals directory instead of extensionless basenames. Animated GIFs remain part of discovery and are no longer mistaken for deleted originals when default conversion is skipped.
- **Specialized orphan cleanup** — specialized page usage is reset before rendering, rebuilt by rendered tags, cleaned in non-development builds, and saved through the shared manifest.
- **Double registration** — processed versions remain registered by `OperationProcessor`; only existing outputs skipped while rebuilding a missing manifest are registered by `BuildTimeProcessor`.
- **Deep permalink and `baseurl` paths** — generated `<img>` and `<source>` paths are root-absolute and include Jekyll's configured `baseurl` without duplicating it. Absolute URLs use the same normalized path.
- **Stale watch components** — each build refreshes the shared config, manifest, provider, and processor used by Liquid tags, allowing new originals and changed tag operations to use current state.
- **Legacy manifest migration (v0.1.10 → v0.1.11)** — manifests from v0.1.10 stored operations without `format`/`quality` and had no `file_digest`. These entries are now detected and cleared on load so existing optimized files are re-registered from disk without reprocessing.
- **Unnecessary reprocessing on render** — `OperationProcessor#process_operation` now checks if the output file already exists and is up-to-date before invoking the provider, preventing redundant Sharp/ImageMagick calls when the manifest is out of sync.
- **ReDoS in Picture Tag adaptor** — the `{% picture ... %}` extraction regex no longer has polynomial backtracking from redundant `\s*` before `%}`.
- **ReDoS in opacity validation** — `OpacityTag` and `WatermarkTag` replaced the `\A\d*\.?\d+\z` regex with `Float()` + rescue, eliminating polynomial backtracking on malformed input.
- **Shell injection in Libvips provider** — all `build_*` methods now return command arrays executed via `Open3.capture3(*array)` (no shell). Chained `&&` commands run as separate Ruby steps, `$(vips header ...)` substitutions are pre-computed in Ruby, and `rm -f` cleanup uses `FileUtils.rm_f`.
- `preset_manager` is now initialized in `site.imgflow_components` for both `BuildTimeProcessor` and `ImgflowTag`, fixing `undefined method 'build_markup_from_preset' for nil` errors.
- Preset tag expansion now uses `Shellwords` to correctly parse quoted image paths and preserves quoted option values containing spaces or Danish characters.
- `BuildTimeProcessor` no longer resets specialized-image `used_on` metadata during incremental builds, preventing deletion of images still used by unrendered pages.
- `post_write` hook now runs specialized-image cleanup only in non-development, non-incremental builds and saves the manifest afterward.
- `ImgflowTag` now checks both manifest existence and the actual output file on disk before reusing a version.
- Default-version up-to-date checks now use source SHA-256 digests and verify the output file exists, regenerating missing or stale versions.
- **SVG processing with libvips** — the libvips provider now uses `vips thumbnail` (the recommended high-level resize API) instead of `vips VipsResize` for all resize operations. `thumbnail` bounds the SVG render size during load, preventing "image too large" errors on SVGs with large viewBoxes (e.g. 10000x8500). This also improves JPEG performance via shrink-on-load. SVG crop operations use `thumbnail --crop` to avoid coordinate mismatches.
- **SVG processing with ImageMagick** — the ImageMagick provider now sets `-density` before SVG input files, telling the rsvg delegate to rasterize at a reasonable resolution instead of the full viewBox (10000x8500 = 85M pixels). This gives ~5x speedup (10s → 2s per conversion) with no quality loss since the image is resized afterward. A warning is logged on the first SVG conversion: if the rsvg delegate is not installed, users are advised to install `librsvg` (macOS: `brew install librsvg`, Ubuntu: `apt install librsvg2-bin`) or use a different provider (sharp/libvips) for SVGs.
- **SVG output filename** — `FilenameGenerator` no longer produces `.svg` as an output format. SVG is a vector input format; image providers always produce raster output. When no format is specified for a specialized version, SVG inputs now fall back to `jpg` (the universal `<img>` fallback).
- **Nil provider crash** — `ProviderRegistry#current_provider` now logs a single centralized warning when no provider is available and returns `nil` instead of raising, eliminating duplicated warning messages in `BuildTimeProcessor` and `ImgflowTag`. Callers check for `nil` and degrade gracefully (rendering the original image without optimization).
- **Unknown operation capability check** — `BaseProvider.supports_operation?` now returns `false` for operations not in the `KNOWN_OPERATIONS` whitelist, preventing providers from claiming support for unrecognized operation types.
- **Provider operation accumulation on failure** — all six providers (`sharp`, `libvips`, `imagemagick`, `imgproxy`, `weserv`, `flyimg`) now reset their operation queue in an `ensure` block. Previously `reset_operations` ran after the provider call, so if the call raised (e.g. an HTTP timeout), operations accumulated across invocations, producing malformed Weserv/Imgproxy/Flyimg URLs with duplicated parameters (`&w=400...&w=800...&output=jpg...&output=avif`) that returned empty responses.
- **Weserv `/dev/shm` exhaustion** — the Weserv nginx proxy_cache stores up to 250MB in `/dev/shm`, but the Docker default 64MB `/dev/shm` filled during bulk test processing, causing `No space left on device` errors that returned empty responses (`EOFError`). The test container now sets `shm_size: 512mb`.
- **Weserv nginx directive duplication on restart** — the startup `sed` command appended `weserv_limit_input_pixels` on every container restart, eventually triggering `nginx: [emerg] "weserv_limit_input_pixels" directive is duplicate`. The command now deletes any existing directive before inserting exactly one.
- **Weserv read timeout** — `Weserv::TIMEOUT` increased from 10 to 30 seconds. The 10s `read_timeout` was too tight under heavy load, causing `EOFError` when the server closed the connection before the response body was fully read.
- **Docker service startup reliability** — `start_services` now uses `docker compose up -d --pull missing --force-recreate --remove-orphans` instead of an unconditional `docker-compose pull` followed by `up -d`. This avoids redundant image pulls, recreates stale containers that reference removed networks, and removes orphaned containers. On failure, recent container logs are dumped automatically. `stop_services` now passes `--remove-orphans` to clean up stale containers on shutdown.
- **Docker status helper HTTP rescue** — `DockerServiceStatus.http_status` now rescues `StandardError` instead of a narrow list, catching `EOFError`/`IOError` that occur when a service closes the connection during startup (previously crashed `start_services` with `EOFError: end of file reached`).

### Changed

- Pinned Docker image tags in `docker-compose.base.yml` for reproducible builds: imgproxy moved from `darthsim/imgproxy:latest` (deprecated Docker Hub location) to `ghcr.io/imgproxy/imgproxy:v4.0.14`; flyimg pinned from `:latest` to `:1.12.5`. Weserv remains on `ghcr.io/weserv/images:5.x` (upstream-recommended branch tag).
- Removed broken `image_compressor` service from `docker-compose.yml` (had no `image:` key, could never start; no provider implementation existed).
- Removed dead `image_compressor_url` config plumbing from `Config`, `test_config.rb`, and `parallel_provider_test_helper.rb` — no provider ever consumed it.
- `docs/docker.md` and `docs/rake.md` updated to reflect new image tags and removed ImageCompressor references.
- Release process in `AGENTS.md` now starts with `rake check_docker_images` to verify image pins are current before releasing.
- The manifest is cache metadata and is no longer published into `_site`; legacy source and destination manifests migrate automatically to `cache_dir` and are removed after a successful save.
- Manifest operation hashes are stored in canonical JSON-compatible form.
- Generated file cleanup extracted into `GeneratedFileCleaner` for path-safe deletion from both source and destination.
- `.gitignore` excludes `.cache/imgflow/`; `docs/installation.md` and `docs/ARCHITECTURE.md` document the `cache_dir` option and updated manifest location.
- Replaced `push_gem.yml` with `release.yml` using official trusted publishing pattern (`rubygems/release-gem@v1`)
- Removed `continue-on-error: true` from CI workflow so tests and style actually gate
- Added `rake version:show`, `rake version:bump`, and `rake version:check_changelog` tasks
- Added CHANGELOG gate to release workflow (fails if entry missing for the version)
- Dropped reek from Gemfile, gemspec, Rakefile, and deleted `.reek.yml` (KISS)
- Deleted `bump_version.sh` and `release.sh` — replaced by rake tasks and release workflow
- Added `bin/install-hooks.sh` for pre-commit (rubocop) and pre-push (rubocop + rspec) hooks
- Removed dead code: `FilenameGenerator#generate_cache_key` (orphaned by the digest-based cache rewrite), unused `require "shellwords"` in libvips (orphaned by the shell-injection fix), unused `require "English"` in base_provider, and the unused `MARKUP_FORMATS` constant in `HtmlGenerator`.
- Added `benchmark ~> 0.5.0` as a runtime dependency because processing metrics require it and Ruby warns it will no longer be a default gem in Ruby 4.0.
- Updated development dependencies: `rubocop` 1.89 → 1.90, `simplecov` 1.1 → 1.2, `parallel` 2.1 → 2.2, `webmock` 3.26.2 → 3.26.4; transitive updates for `commonmarker`, `google-protobuf`, `rbs`, `ruby-lsp`, `sass-embedded`. Remaining outdated gems (`liquid`, `rouge`, `terminal-table`, `unicode-display_width`, `objective_elements`, `diff-lcs`, `json`) are blocked by Jekyll 4.x dependency constraints.
- Gemspec `icon_uri` updated from `v0.1.10` to `v0.1.11`; gemspec description now lists all six providers; `.DS_Store` files excluded from the packaged gem.
- README and docs updated: Docker service ports corrected to the new `.env.test` allocation (4022/4026/4030), `cache_dir` and preset usage documented, `parallel:slow` description corrected to reflect the dynamic work queue.
- **Gemfile/gemspec DRY refactor** — development dependencies are now declared only in the `Gemfile`, not duplicated in the gemspec. The Gemfile uses the `gemspec` directive to pull in runtime dependencies automatically, eliminating version drift between the two files. The gemspec retains only runtime dependencies (`benchmark`, `fastimage`, `jekyll`) and metadata. This follows the [rubygems guide](https://github.com/rubygems/guides/blob/main/gemfile-and-gemspec.md) best practice: runtime deps in gemspec (wide constraints), dev deps in Gemfile (tight constraints, groups, `require: false`).
- `docs/development.md` updated: release process rewritten to reflect the rake-task/GitHub-Actions workflow (was still describing deleted shell scripts); "Adding Dependencies" section documents the Gemfile/gemspec split; configuration files section describes the new `gemspec` directive pattern.
- `docs/installation.md` updated: publishing section rewritten to describe the trusted-publishing workflow instead of manual `gem push`; development installation section updated with current version and `gemspec` directive note; stale `0.1.0` version references updated to `0.1.11`.
- **Documentation DRY consolidation** — eliminated content duplication across docs to prevent drift:
  - Deleted stale `docs/template/{tags,presets,preset-examples}.md` (the template→usage copy system was unmaintained; `presets.md` template documented an obsolete `_IF*.html` mechanism). Removed the `rake generate_docs` task and all references to it.
  - Rewrote `docs/development.md` to link to canonical sources instead of duplicating rake tasks (3×), Docker commands (3×), testing commands (2×), the file tree (duplicates ARCHITECTURE.md), and the release process (duplicates AGENTS.md). Reduced from 297 to 118 lines.
  - Rewrote `docs/README.md` as a lean documentation index — removed duplicated quick-reference blocks, key files list, and architecture summary. Links to canonical docs instead.
  - Trimmed `docs/installation.md`: backend priority list now links to `providers.md` instead of duplicating benchmark numbers; publishing section links to `AGENTS.md` instead of duplicating the release procedure.
  - Trimmed `README.md`: removed duplicated benchmark table (links to `providers.md`); consolidated the two config blocks into one.
  - Trimmed `docs/ARCHITECTURE.md`: config example replaced with a pointer to `installation.md`; fixed `picture_tag_adapter.rb` → `picture_tag_adaptor.rb` spelling.
  - Trimmed `docs/scripts.md`: removed duplicated rake task listing (links to `rake.md`).
  - Fixed broken links: `PARALLEL_TESTING.md` → `parallel_testing.md` in `docs/testing.md`.
- **Performance benchmark metrics** — added `ProcessingStats` class (`lib/jekyll-imgflow/processing_stats.rb`) that tracks build-level cache hit/miss counts, wall-clock timing grouped by primary operation, and compression ratios per format. The benchmark now compares clean and cached builds for every provider and reports cache performance, operation timing, and compression ratios in JSON and markdown. Deleted `docs/PERFORMANCE_BENCHMARK_ARCHITECTURE.md` after implementing the relevant enhancements; parallel processing metrics were removed because production processing remains sequential.

## [0.1.10] - 2026-08-18

### Added

- **Project branding assets** — moved the full logo and icon to `docs/assets/images/` with project-specific names for GitHub documentation and the next RubyGems release.
- README branding now uses the repository logo, and the gemspec defines a stable `icon_uri` for the `0.1.10` release.

### Fixed

- Release script now stages tracked changes only, preventing unrelated untracked files from being included in a release commit.
- Version bumping now synchronizes `Gemfile.lock` and carries `[Unreleased]` notes into the new version section.

### Changed

- Release script now creates the GitHub Release page and tag together through `gh release create`, avoiding tag-without-release failures.
- Renamed `AI_INSTRUCTIONS.md` to `AGENTS.md` and updated tool-specific instruction references.
- Updated release documentation with the single-command release workflow and GitHub CLI prerequisite.
- Improved `AGENTS.md` with non-hardcoded test guidance, explicit release prerequisites, a manual-tag prohibition, and supplemental DeepWiki/GitHub resource links.

## [0.1.9] - 2026-08-18

### Added

- Tests for quoted image paths, site-root paths, and exact originals-relative path resolution.
- Real-world integration coverage for preserving nested output directories and validating generated HTML paths.

### Fixed

- **Generated post path compatibility** — image references that already include the configured originals directory, such as `assets/images/originals/subdir/photo.jpg`, are now resolved as site-root paths instead of incorrectly prepending the originals directory a second time.
- **Canonical image path documentation** — user-facing examples now use paths relative to `imgflow.originals`, such as `subdir/more_subdir/photo.jpg`, without exposing the `assets/` directory.
- **Release tooling** — version consistency checks and release-note extraction now work correctly with an `[Unreleased]` section on macOS and Linux.

## [0.1.8] - 2026-08-17

### Added

- **VS Code companion extension** — added the `jekyll-imgflow-vscode` companion extension. It provides image filename autocomplete for `{% imgflow %}` tags in Markdown and Liquid files, auto-discovers `imgflow.originals` from `_config.yml`, and watches the originals directory for changes.
- Tests for nested original image resolution, custom `originals` directories, and preserved output directory structure.

### Fixed

- **Nested original image resolution** — `{% imgflow valdemar/photo.jpg %}` now correctly resolves to `assets/images/originals/valdemar/photo.jpg` instead of `assets/images/valdemar/photo.jpg`. Previously any path containing `/` was joined directly to the site source, ignoring the configured `originals` directory.
- **Output directory structure preservation** — optimized images now mirror the original directory structure under `assets/images/optimized/`. This prevents name collisions when two different folders contain images with the same basename (e.g. `valdemar/photo.jpg` vs `familie/photo.jpg`).
- **Build-time manifest path storage** — default versions are written to the source directory, but the manifest relative path was computed against `site.dest`, producing incorrect `/_site/...` entries. Now computed against `site.source` so manifest URLs are correct.
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
