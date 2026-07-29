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
rake generate_docs        # Update docs from templates
```

## 📋 All Tasks

### 🧪 Comprehensive Testing

- `rake test_comprehensive` - Run all test suites (replaces run_all_tests.sh)
- `rake test_providers` - Run provider tests only
- `rake test_jekyll` - Run Jekyll integration tests only
- `rake test_picture` - Run Picture Tag integration tests only
- `rake test` - Run tests only
- `rake spec` - Run tests with coverage
- `rake quick` - Style + tests (fast)
- `rake quality` - All quality checks (slow)

### 🚀 Performance

- `rake performance_quick` - Quick CLI tools test
- `rake performance_benchmark` - Comprehensive benchmark
- `rake performance_test` - Performance via RSpec

### 🔧 Setup & Services

- `rake download_test_images` - Download test images
- `rake check_services` - Check service availability
- `rake check_gems` - Check gem dependencies

### 📚 Documentation

- `rake docs` - Show documentation structure
- `rake generate_docs` - Generate docs from templates
- `rake doc` - Generate YARD API docs

### 🛠️ Code Quality

- `rake rubocop` - Check code style
- `rake rubocop_fix` - Auto-fix style issues
- `rake reek` - Check code smells
- `rake bundler_audit` - Security scan

### 📦 Build & Install

- `rake install_local` - Build and install gem locally
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

### Before Committing

```bash
rake quick
```

### Full Testing

```bash
rake quality
rake test_comprehensive
rake performance_benchmark
```

### Development Documentation

```bash
# Edit templates in docs/template/
rake generate_docs
rake docs
```

## ⚡ Performance Tasks Explained

| Task | Duration | What it tests | When to use |
|------|----------|---------------|------------|
| `performance_quick` | 10s | CLI tools only | Quick checks |
| `performance_benchmark` | 5-10m | All providers | Detailed analysis |
| `performance_test` | 5-10m | Via RSpec | CI/CD testing |

## 🔍 Service Check

`rake check_services` tests:

- **CLI Tools**: vips, magick, sharp
- **HTTP Services**: Imgproxy, Weserv, Flyimg, ImageCompressor
- **Docker**: ImageCompressor CLI image

## 🔄 Migration from Shell Scripts

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

## 📝 Documentation System

ImgFlow uses templates:

1. Edit files in `docs/template/`
2. Run `rake generate_docs`
3. Docs sync to `docs/usage/` and `lib/jekyll-imgflow/`

## 🆘 Troubleshooting

**Tests failing?**

```bash
rake check_services  # Check services
rake check_gems      # Check gems
rake download_test_images  # Get test images
```

**Documentation outdated?**

```bash
rake generate_docs
```

**Performance issues?**

```bash
rake performance_quick  # Quick check
```

That's it! Simple and effective. 🚀
