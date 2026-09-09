# ImgFlow Rake Tasks

Simple guide to all available Rake tasks in ImgFlow.

## 🚀 Quick Commands

```bash
# See all available tasks
rake help

# Comprehensive testing (replaces run_all_tests.sh)
rake test_comprehensive

# Quick development setup
rake download_test_images  # Get test images
rake check_services        # Check if services are running
rake test                 # Run tests

# Performance testing
rake performance_quick     # Quick check (10 seconds)
rake performance_benchmark # Full benchmark (5-10 minutes)

# Documentation
rake docs                 # Show docs structure
```

## 📋 All Tasks

### 🧪 Comprehensive Testing

- `rake test_comprehensive` - Run all test suites (replaces run_all_tests.sh)
- `rake test_providers` - Run provider tests only
- `rake test_jekyll` - Run Jekyll integration tests only
- `rake test_picture` - Run Picture Tag integration tests only
- `rake test` - Run tests only
- `rake spec` - Run tests with coverage
- `rake spec_slow` - Run slow tests sequentially (tagged `:slow`)
- `rake spec_fast` - Run fast tests only (excludes `:slow`, `:external`, `:provider`)
- `rake quick` - Style + fast tests (excludes `:slow` and `:external`)
- `rake ci` - Run the same RuboCop and RSpec checks as GitHub Actions locally
- `rake quality` - All quality checks (slow)

### ⚡ Parallel Testing

- `rake parallel:test` - Run fast tests in parallel (n-1 cores, excludes slow/external)
- `rake parallel:test_coverage` - Run fast tests in parallel with coverage (n-2 cores)
- `rake parallel:slow` - Run slow tests in parallel (dynamic work queue across providers and test categories)
- `rake parallel:test_files[files]` - Run specific test files in parallel

### 🚀 Performance

- `rake performance_quick` - Quick CLI tools test
- `rake performance_benchmark` - Comprehensive benchmark
- `rake performance_test` - Performance via RSpec

### 🔧 Setup & Services

- `rake download_test_images` - Download test images
- `rake start_services` - Start Docker test services (pulls missing images, recreates stale containers, removes orphans)
- `rake stop_services` - Stop Docker test services
- `rake check_services` - Check service availability
- `rake check_docker_images` - Check if pinned Docker images are outdated (run before releases)
- `rake check_gems` - Check gem dependencies

### 📚 Documentation

- `rake docs` - Show documentation structure
- `rake doc` - Generate YARD API docs

### 🛠️ Code Quality

- `rake rubocop` - Check code style
- `rake rubocop_fix` - Auto-fix style issues
- `rake bundler_audit` - Security scan

### 📦 Build & Install

The preset tasks are enabled in consuming sites by adding
`require "jekyll-imgflow/tasks"` to the site's `Rakefile`.

- `rake install_local` - Build and install gem locally
- `rake imgflow:presets` - List built-in presets and their install status
- `rake imgflow:install_presets` - Copy built-in presets into the site's `_data/imgflow/presets/`
- `rake 'imgflow:install_presets[true]'` - Overwrite modified preset copies
- `rake help` - Show this help

## 🎯 Common Workflows

### Comprehensive Testing (New)

```bash
rake test_comprehensive     # All test suites with pre-flight checks
rake test_providers         # Provider tests only
rake test_jekyll           # Jekyll integration only
rake test_picture          # Picture tag integration only
```

### First Time Setup

```bash
rake download_test_images
rake check_services
rake test
```

### Before Committing or Pushing

```bash
rake quick  # Fast local feedback; excludes slow and external tests
rake ci     # CI-equivalent gate; includes external tests that can run locally
```

The pre-push hook runs `rake ci` automatically, so the same test command used
by GitHub Actions is checked before a push. Install or refresh the hooks with:

```bash
bin/install-hooks.sh
```

GitHub Actions uses Ubuntu 26.04, Ruby 3.4.10, libvips/ImageMagick, and the
pinned Sharp CLI version from `package.json`. Local native tools still depend
on the host OS, but `rake ci` uses the same RSpec tags and Ruby version target.

### Full Testing

```bash
rake quality
rake test_comprehensive
rake performance_benchmark
```

## ⚡ Performance Tasks Explained

| Task | Duration | What it tests | When to use |
| --- | --- | --- | --- |
| `performance_quick` | 10s | CLI tools only | Quick checks |
| `performance_benchmark` | 5-10m | All providers | Detailed analysis |
| `performance_test` | 5-10m | Via RSpec | CI/CD testing |

## 🔍 Service Check

`rake check_services` tests:

- **CLI Tools**: vips, magick, sharp
- **HTTP Services**: Imgproxy, Weserv, Flyimg

## Docker Image Version Check

`rake check_docker_images` queries each upstream registry (GHCR, Docker Hub) for
the latest version tags and compares them against the pins in
`docker-compose.base.yml`. Run this before releasing to catch stale image pins.

```bash
rake check_docker_images              # report only
STRICT=true rake check_docker_images  # exit 1 if any pin is outdated
```

If updates are found, edit `docker-compose.base.yml`, then run `rake start_services`
to recreate containers with the new images before proceeding with the release.
`start_services` uses `--pull missing` so only newly-pinned images are fetched.

## Migration from Shell Scripts

**Replaced `run_all_tests.sh`:**

- ❌ `./run_all_tests.sh` → ✅ `rake test_comprehensive`
- ❌ `./run_all_tests.sh --quick` → ✅ `rake test_providers`
- ❌ `./run_all_tests.sh --jekyll` → ✅ `rake test_jekyll`
- ❌ `./run_all_tests.sh --picture` → ✅ `rake test_picture`

**Benefits:**

- ✅ Cross-platform (works on Windows, macOS, Linux)
- ✅ Better error handling (Ruby exceptions)
- ✅ Integrated with existing Rake tasks
- ✅ Consistent interface

## 🆘 Troubleshooting

**Tests failing?**

```bash
rake check_services  # Check services
rake check_gems      # Check gems
rake download_test_images  # Get test images
```

**Performance issues?**

```bash
rake performance_quick  # Quick check
```

That's it! Simple and effective. 🚀
