# AI Instructions — Jekyll ImgFlow

> **Single source of truth for all AI assistants working on this project.**
> Tool-specific files (`CLAUDE.md`, `.windsurf/rules`, `.devin/instructions.md`) reference this document.

## Project Summary

Jekyll ImgFlow is a Jekyll plugin for automatic image optimization with multiple providers (Sharp, ImageMagick, LibVips, Imgproxy, Weserv, Flyimg) and formats (WebP, AVIF, JPG, PNG). It generates responsive images during Jekyll build and render time.

- **Language:** Ruby 3.4+
- **Framework:** Jekyll 4.x plugin (Liquid tags + build hooks)
- **Gem:** `jekyll-imgflow` v0.1.0
- **License:** AGPL-3.0-or-later
- **Author:** Svend Gundestrup (<svend@gundestrup.dk>)
- **Repo:** <https://github.com/gundestrup/jekyll-imgflow>

## Key Files & Structure

The full file tree with descriptions is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Key entry points:

- `lib/jekyll-imgflow.rb` — Entry point, requires all components
- `lib/jekyll-imgflow/imgflow_tag.rb` — `{% imgflow %}` Liquid tag (main render-time entry)
- `lib/jekyll-imgflow/hooks.rb` — Jekyll site lifecycle hooks
- `lib/jekyll-imgflow/build_time_processor.rb` — Build-time image processing
- `lib/jekyll-imgflow/manifest_manager.rb` — Image version tracking (single source of truth)
- `lib/jekyll-imgflow/providers/` — Provider implementations (see [docs/providers.md](docs/providers.md))
- `lib/jekyll-imgflow/tags/` — Tag validation classes
- `spec/` — RSpec test suite (~980 examples)
- `docs/` — All project documentation

## Documentation Index

### Architecture & Design

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Full component architecture, data flow, and design decisions
- [docs/README.md](docs/README.md) — Documentation index and quick reference

### Setup & Configuration

- [docs/installation.md](docs/installation.md) — Installation guide
- [docs/providers.md](docs/providers.md) — Provider setup and comparison
- [docs/docker.md](docs/docker.md) — Docker services for HTTP providers
- [_config.yml](_config.yml) — Jekyll site configuration with `imgflow:` section

### Usage

- [docs/usage/tags.md](docs/usage/tags.md) — Available Jekyll tags
- [docs/usage/presets.md](docs/usage/presets.md) — Preset system
- [docs/usage/preset-examples.md](docs/usage/preset-examples.md) — Preset examples
- [docs/picture_tag_migration.md](docs/picture_tag_migration.md) — Migrate from Jekyll Picture Tag

### Development

- [docs/development.md](docs/development.md) — Development guide and workflow
- [docs/testing.md](docs/testing.md) — Testing guide
- [docs/parallel_testing.md](docs/parallel_testing.md) — Parallel testing setup
- [docs/rake.md](docs/rake.md) — All Rake tasks
- [docs/scripts.md](docs/scripts.md) — Development scripts reference

### Testing

- [spec/support/HELPER_METHODS.md](spec/support/HELPER_METHODS.md) — Test helper methods reference
- [spec/support/TEST_PICTURES_README.md](spec/support/TEST_PICTURES_README.md) — Test image fixtures

## Development Commands

See [docs/rake.md](docs/rake.md) for the full list of Rake tasks and [docs/development.md](docs/development.md) for the development workflow. Quick reference:

```bash
rake quick          # Style + tests (fastest)
rake test           # All tests
rake quality        # Full quality checks
rake rubocop        # Check code style
rake rubocop_fix    # Auto-fix style issues
rake reek           # Code smell detection
rake bundler_audit  # Security scan
```

See [docs/parallel_testing.md](docs/parallel_testing.md) for parallel test setup and [docs/scripts.md](docs/scripts.md) for utility scripts.

## Code Quality Tools

| Tool | Config | Purpose |
| --- | --- | --- |
| RuboCop | `.rubocop.yml` | Code style (Ruby 3.4, double quotes, max line 100) |
| Reek | `.reek.yml` | Code smell detection |
| RSpec | `.rspec` / `.rspec_parallel` | Test framework with coverage |
| SimpleCov | (in spec_helper) | Coverage reporting |
| Bundler Audit | — | Security vulnerability scanning |
| Parallel Tests | `.parallel_tests.yml` | Parallel test execution |

## Coding Conventions

- **Frozen string literals:** All files must start with `# frozen_string_literal: true`
- **String quotes:** Double quotes (`"..."`) enforced by RuboCop
- **Line length:** Max 100 characters
- **Method length:** Max 50 lines (RuboCop)
- **Cyclomatic complexity:** Max 12 (RuboCop)
- **Hash syntax:** Ruby 1.9+ syntax (`key: value`), not hash rockets
- **No trailing commas** in hash literals
- **Namespace:** `JekyllImgFlow::` for library code, `Jekyll::ImgflowTag` for the Liquid tag
- **Providers:** Inherit `JekyllImgFlow::Providers::BaseProvider`, implement `available?` and `execute`
- **Tags:** Inherit `JekyllImgFlow::Tags::BaseTag`, implement `process`
- **Error handling:** Rescue specific errors, not bare `rescue` or `rescue Exception`

## Architecture Notes

**Full architecture documentation:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

Key points (see the linked doc for details):

- **Two processing flows:** Build-Time (pre-generate defaults) and Runtime (on-demand specialized versions)
- **ManifestManager** is the single source of truth for image versions, persisted to `_site/assets/images/imgflow-manifest.json`
- **ProviderRegistry** auto-discovers providers from `lib/jekyll-imgflow/providers/*.rb`; first available from `config.backend_priority` is used
- **TagRegistry** auto-discovers tags from `lib/jekyll-imgflow/tags/*_tag.rb`

## Testing Conventions

**Full testing guide:** [docs/testing.md](docs/testing.md)
**Test helper reference:** [spec/support/HELPER_METHODS.md](spec/support/HELPER_METHODS.md)
**Parallel testing:** [docs/parallel_testing.md](docs/parallel_testing.md)

Key rules:

- **1064 examples, 0 failures** is the baseline — never introduce regressions
- Use `:unit` tag for unit tests, `:slow` tag for slow tests (excluded by default)
- Mock Docker services in tests; do not require real HTTP providers for unit tests
- Reset singleton methods and shared state in `after` blocks to prevent cross-test contamination
- Tests should assert concrete behavior (outputs, side effects, return values), not just absence of errors

### Test Infrastructure Lessons (v0.1.6 wipe bug)

The v0.1.6 bug (optimized images wiped from `_site` on rebuild) went undetected because:

1. **`keep_files: ["assets"]` in spec_helper.rb** — this prevented Jekyll from cleaning `_site/assets/` between builds, masking the exact bug. **Removed in v0.1.7** — do not re-add it.
2. **Most tests use mock sites (RSpec doubles)** — they never run `jekyll build` end-to-end, so they never exercise Jekyll's site reset behavior.
3. **No file placement verification** — tests checked that files existed *somewhere*, but not whether they were in the source directory (correct) vs `_site` (bug).
4. **No second-build tests** — only `spec/realworld_build_spec.rb` (tagged `:slow`) runs `jekyll build` twice to check for the wipe.

To prevent similar bugs: run `bundle exec rspec --tag slow` before releases, and add file-placement assertions to integration tests.

## Release Process

See [docs/scripts.md](docs/scripts.md) for release scripts reference.

```bash
./bump_version.sh patch    # or minor/major
./release.sh               # Full release with checks
```

## Do NOT

- Do not modify production code beyond what is necessary for the task
- Do not add or remove comments unless explicitly requested
- Do not create unnecessary files (helpers, scripts, docs) unless required
- Do not bypass RuboCop rules — fix the code, not the config
- Do not use `puts`/`print` in production code — use `Jekyll.logger`
- Do not rescue `Exception` — rescue `StandardError` or specific error classes
- Do not use `eval`, `class_eval`, or `send` with user input
