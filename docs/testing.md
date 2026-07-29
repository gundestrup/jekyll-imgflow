# ImgFlow Testing Guide

## Quick Start

```bash
bundle exec rspec              # Run all tests
bundle exec rspec --parallel   # Run in parallel (faster)
```

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

**See:** [PARALLEL_TESTING.md](PARALLEL_TESTING.md) for detailed parallel testing setup

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

- [PARALLEL_TESTING.md](PARALLEL_TESTING.md) - Parallel testing details
- [development.md](development.md) - Development workflow
- [ARCHITECTURE.md](ARCHITECTURE.md) - Component architecture
- [picture_tag_migration.md](picture_tag_migration.md) - Picture Tag migration
- [scripts.md](scripts.md) - Development scripts and utilities
