# ImgFlow Testing Guide

## Quick Start

```bash
rake ci                        # CI-equivalent local gate
bundle exec rspec              # Run all tests
bundle exec rspec --parallel   # Run in parallel (faster)
```

`rake ci` is the recommended pre-push check. It runs RuboCop and
`bundle exec rspec --tag ~slow`, matching `.github/workflows/ci.yml`. The
pre-push Git hook runs it automatically. Install the hook with:

```bash
bin/install-hooks.sh
```

The CI environment is pinned to Ubuntu 26.04, Ruby 3.4.10, and the Sharp CLI
version declared in `package.json`. Install that CLI locally with:

```bash
SHARP_CLI_VERSION="$(node -p 'require("./package.json").devDependencies["sharp-cli"]')"
npm install -g "sharp-cli@${SHARP_CLI_VERSION}"
```

Docker-backed HTTP provider tests are intentionally run locally rather than in
CI. Start them with `rake start_services` when running those provider tests.

## Test Structure

### Core Tests

- **`config_spec.rb`** - Configuration system
- **`parser_spec.rb`** - Markup parsing  
- **`operation_processor_spec.rb`** - Image operations
- **`provider_interface_spec.rb`** - Provider compatibility

### Tag Tests  

- **`tags/*_spec.rb`** - Individual tag validation
- **`tags_system_spec.rb`** - Tag system integration
- **`imgflow_tag_spec.rb`** - Main ImgFlow tag

### Integration Tests

- **`jekyll_integration_spec.rb`** - Jekyll integration
- **`picture_tag_*_spec.rb`** - Picture Tag compatibility
- **`imgflow_system_spec.rb`** - End-to-end system tests

**See:** [picture_tag_migration.md](picture_tag_migration.md) for Picture Tag migration details

### Performance Tests

- **`performance_benchmark_spec.rb`** - Performance benchmarks

## Architecture Reference

**See:** [ARCHITECTURE.md](ARCHITECTURE.md) for detailed component information

## Parallel Testing

**See:** [parallel_testing.md](parallel_testing.md) for detailed parallel testing setup

### Quick Commands

```bash
bundle exec rspec --parallel                    # Parallel execution
TEST_PROVIDER=sharp bundle exec rspec         # Test specific provider
PERFORMANCE=true bundle exec rspec             # Sequential performance tests
```

```bash
# Test with Libvips + default image
IMGFLOW_TEST_PROVIDER=libvips bundle exec rspec spec/tags/resize_tag_spec.rb

# Test with Sharp + all formats  
IMGFLOW_TEST_PROVIDER=sharp bundle exec rspec spec/tags/resize_tag_spec.rb

# Test meta-testing with specific provider
IMGFLOW_TEST_PROVIDER=libvips bundle exec rspec spec/provider_meta_testing_spec.rb

# Test with different image sets
TEST_PICTURES=full bundle exec rspec spec/provider_meta_testing_spec.rb
TEST_PICTURES=quick bundle exec rspec spec/provider_meta_testing_spec.rb```

## Cleanup

### Quick Commands
```bash
rm -rf tmp/                                    # Remove test artifacts
lsof -ti:4000,4010-4016 | xargs kill -9       # Kill test servers
ruby scripts/cleanup_test_artifacts.rb         # Full cleanup script
```

**See:** [development.md](development.md) for detailed development workflow

## Running Tests

```bash
bundle exec rspec              # All tests
bundle exec rspec --parallel   # Parallel execution
bundle exec rspec --format documentation  # Verbose output
```

## Quick Reference

### Debugging

```bash
TEST_PROVIDER=sharp bundle exec rspec           # Test specific provider
bundle exec rspec spec/parser_spec.rb           # Test specific file
```

### Test Groups

```bash
bundle exec rspec spec/picture_tag_*_spec.rb    # Picture Tag tests
bundle exec rspec spec/provider_interface_spec.rb # Provider tests
```

---

**Related Documents:**

- [parallel_testing.md](parallel_testing.md) - Parallel testing details
- [development.md](development.md) - Development workflow
- [ARCHITECTURE.md](ARCHITECTURE.md) - Component architecture
- [picture_tag_migration.md](picture_tag_migration.md) - Picture Tag migration
- [scripts.md](scripts.md) - Development scripts and utilities
