# Scripts & Utilities

## Overview

ImgFlow includes various scripts for development, testing, and maintenance tasks.

## Development Scripts

### Debugging Tools

```bash
ruby scripts/debug_picture_tag.rb      # Test Picture Tag adaptor
ruby scripts/debug_test_url.rb         # Test URL handling
ruby scripts/test_enhanced_adaptor.rb  # Test adaptor with attributes
ruby scripts/test_html_generator.rb    # Test HTML generation
```

### Testing Tools

```bash
./scripts/run_tests.sh                # Run test suite
ruby scripts/test_logger.rb status    # Show test status
ruby scripts/performance_benchmark.rb # Run performance tests
```

### Cleanup Tools

```bash
ruby scripts/cleanup_test_artifacts.rb # Clean test files and services
```

## Bin Scripts

### CLI Tools

```bash
bin/imgflow_migrate_presets            # Migrate Picture Tag presets
bin/imgflow_migrate_presets --preview  # Preview migration
```

### Build Scripts

```bash
./bump_version.sh patch               # Bump version (patch/minor/major)
./release.sh                         # Release with checks
```

## Quick Reference

| Script | Purpose | Usage |
|--------|---------|-------|
| `debug_picture_tag.rb` | Picture Tag adaptor testing | `ruby scripts/debug_picture_tag.rb` |
| `debug_test_url.rb` | URL testing | `ruby scripts/debug_test_url.rb` |
| `test_enhanced_adaptor.rb` | Adaptor attributes | `ruby scripts/test_enhanced_adaptor.rb` |
| `test_html_generator.rb` | HTML generation | `ruby scripts/test_html_generator.rb` |
| `run_tests.sh` | Test runner | `./scripts/run_tests.sh` |
| `test_logger.rb` | Test status | `ruby scripts/test_logger.rb status` |
| `performance_benchmark.rb` | Performance | `ruby scripts/performance_benchmark.rb` |
| `cleanup_test_artifacts.rb` | Cleanup | `ruby scripts/cleanup_test_artifacts.rb` |
| `imgflow_migrate_presets` | Preset migration | `bin/imgflow_migrate_presets` |
| `bump_version.sh` | Version bump | `./bump_version.sh patch` |
| `release.sh` | Release | `./release.sh` |

## Development Workflow

```bash
# 1. Debug issues
ruby scripts/debug_picture_tag.rb

# 2. Run tests
./scripts/run_tests.sh

# 3. Check status
ruby scripts/test_logger.rb status

# 4. Clean up if needed
ruby scripts/cleanup_test_artifacts.rb
```

## Migration Workflow

```bash
# 1. Preview migration
bin/imgflow_migrate_presets --preview

# 2. Perform migration
bin/imgflow_migrate_presets

# 3. Test results
bundle exec rspec spec/picture_tag_*_spec.rb
```

## Performance Testing

```bash
# Quick performance check
ruby scripts/performance_benchmark.rb

# Or via Rake task
rake performance_benchmark

# Or via RSpec
PERFORMANCE=true rake performance_test

# View results
cat docs/performance/README.Performance.md
```

## Comprehensive Testing (via Rake Tasks)

```bash
# All test suites
rake test_comprehensive

# Individual test suites
rake test_providers     # Provider tests only
rake test_jekyll        # Jekyll integration only
rake test_picture       # Picture tag integration only

# Pre-flight checks
rake check_services     # Service availability
rake check_gems         # Gem dependencies
```

---

**Related:**

- [development.md](development.md) - Development workflow
- [testing.md](testing.md) - Testing guide
- [picture_tag_migration.md](picture_tag_migration.md) - Migration guide
