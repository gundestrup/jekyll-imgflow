# ImgFlow Development Guide

## Quick Start

```bash
rake              # Run all checks
rake quick        # Quick check (style + tests)
```

## Setup

```bash
./create-test-images.sh  # Download test images (one-time)
```

## Architecture

**See:** [ARCHITECTURE.md](ARCHITECTURE.md) for detailed component architecture and data flow

### Key Components

- **Parser** - Input validation and markup parsing
- **Tags** - Operation parameter validation
- **Providers** - Image processing services
- **HTML Generator** - Unified HTML output generation

### Processing Paths

1. **Build-time** - Hooks → Processor → Image generation
2. **Template-time** - Liquid tags → ImgflowTag → HTML output

## Development Workflow

1. Edit code in `lib/` directory
2. Test changes: `rake quick`
3. Full check before commit: `rake`

### Quick Commands

```bash
rake quick                    # Style + tests (fastest)
rake test                     # All tests
rake quality                  # Full quality checks
rake check_services            # Verify Docker services
rake parallel:test            # Parallel testing (faster)
```

## Testing

### Run Tests

```bash
bundle exec rspec              # All tests
bundle exec rspec --parallel   # Parallel execution
```

**Testing Guide:** See [testing.md](testing.md) for comprehensive testing information

### Test Services

```bash
docker-compose -f docker-compose.test.yml --env-file .env.test up -d
./check-test-services.sh      # Verify services
```

### Provider Types

- **HTTP API Services** (Docker): Imgproxy, Weserv, Flyimg
- **CLI Tools** (Local): ImageMagick, LibVips, Sharp

**Provider Details:** See [providers.md](providers.md) for complete provider comparison

## Commands

### Testing

```bash
rake test         # Tests only
rake spec         # Tests + coverage
rake quick        # Fast check (style + tests)
```

### Code Quality

```bash
rake rubocop      # Code style
rake rubocop_fix  # Auto-fix issues
rake reek         # Code smells
rake bundler_audit # Security check
```

### Development

```bash
rake install_local # Install gem locally
```

## File Structure

```
lib/jekyll-imgflow/
├── config.rb                    # Configuration management
├── parser.rb                    # Input validation and parsing
├── html_generator.rb            # Unified HTML generation
├── imgflow_tag.rb               # Main ImgFlow tag
├── picture_tag_adaptor.rb       # Picture Tag compatibility
├── picture_tag_preset_migrator.rb # Preset migration
├── operation_processor.rb       # Image operations
├── provider_registry.rb         # Provider management
├── providers/                   # Image processing providers
│   ├── base_provider.rb         # Base interface
│   ├── sharp.rb                 # Sharp CLI provider
│   ├── imagemagick.rb           # ImageMagick CLI provider
│   ├── libvips.rb               # LibVips CLI provider
│   ├── imgproxy.rb              # ImgProxy HTTP provider
│   ├── weserv.rb                # Weserv HTTP provider
│   └── flyimg.rb                # Flyimg HTTP provider
├── tags/                        # Operation validators
│   ├── base_tag.rb              # Shared functionality
│   ├── resize_tag.rb            # Resize validation
│   ├── crop_tag.rb              # Crop validation
│   ├── quality_tag.rb           # Quality validation
│   ├── format_tag.rb            # Format validation
│   └── tag_registry.rb          # Tag registration
└── hooks.rb                     # Jekyll build hooks
```

## Adding New Providers

1. Create provider class in `lib/jekyll-imgflow/providers/`
2. Inherit from `BaseProvider`
3. Implement required methods: `resize`, `crop`, etc.
4. Add to `provider_registry.rb`
5. Add tests
6. Update Docker services if HTTP API

## Picture Tag Migration

**Migration Guide:** See [picture_tag_migration.md](picture_tag_migration.md) for complete migration instructions

### CLI Tool

```bash
bin/imgflow_migrate_presets --preview  # Preview migration
bin/imgflow_migrate_presets            # Migrate presets
```

## Release Process

The version bump and release scripts keep `version.rb`, `Gemfile.lock`, and
`CHANGELOG.md` synchronized. The release script runs quality checks, builds the
gem, pushes the commit, creates the GitHub tag and Release page together, and
starts the RubyGems publishing workflow.

Prerequisites:

- Authenticate GitHub CLI once with `gh auth login`.
- Keep the working tree free of untracked files.
- Add or review the current notes under `## [Unreleased]`.

```bash
./bump_version.sh patch  # or minor/major; moves Unreleased notes to the version
# Review and complete the new version section in CHANGELOG.md
./release.sh             # quality checks, gem build, tag, GitHub Release, and publish workflow
```

Do not create the tag or GitHub Release page manually. The release script does
both together to prevent a tag from being published without a Release page.

## Troubleshooting

### Tests Failing

```bash
bundle install      # Update dependencies
rm -rf tmp/         # Clear cache
./create-test-images.sh  # Refresh test images
```

### Docker Issues

```bash
./check-test-services.sh  # Diagnose
docker-compose -f docker-compose.test.yml restart  # Restart
```

## Scripts

- `create-test-images.sh` - Download test images
- `check-test-services.sh` - Health check
- `bump_version.sh` - Version bumping
- `release.sh` - Release automation

---

## Quick Reference

### Essential Files

- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Detailed component architecture
- **[testing.md](testing.md)** - Comprehensive testing guide  
- **[providers.md](providers.md)** - Provider comparison and setup
- **[picture_tag_migration.md](picture_tag_migration.md)** - Picture Tag migration
- **[PARALLEL_TESTING.md](PARALLEL_TESTING.md)** - Parallel testing setup
- **[docker.md](docker.md)** - Docker services configuration
- **[scripts.md](scripts.md)** - Development scripts and utilities

### Core Code Files

- **`lib/jekyll-imgflow.rb`** - Main module and requires
- **`lib/jekyll-imgflow/config.rb`** - Configuration management
- **`lib/jekyll-imgflow/parser.rb`** - Input validation and parsing
- **`lib/jekyll-imgflow/html_generator.rb`** - Unified HTML generation
- **`lib/jekyll-imgflow/imgflow_tag.rb`** - Main ImgFlow tag
- **`lib/jekyll-imgflow/picture_tag_adaptor.rb`** - Picture Tag compatibility
- **`lib/jekyll-imgflow/provider_registry.rb`** - Provider management

### Test Files

- **`spec/spec_helper.rb`** - Test configuration and setup
- **`spec/imgflow_system_spec.rb`** - End-to-end system tests
- **`spec/provider_interface_spec.rb`** - Provider compatibility tests
- **`spec/picture_tag_integration_spec.rb`** - Picture Tag integration

### Configuration Files

- **`Rakefile`** - Build and test tasks
- **`docker-compose.test.yml`** - Test Docker services
- **`.env.test`** - Test environment variables
- **`Gemfile`** - Ruby dependencies

### Key Rake Tasks

```bash
# Development Workflow
rake quick                    # Style + tests (fastest)
rake quality                  # Full quality checks
rake                         # Default = quality

# Testing
rake test                     # All tests  
rake spec                     # RSpec tests
rake parallel:test            # Parallel testing (faster)
rake test_comprehensive       # Detailed test suite

# Individual Test Groups
rake test_core                # Core system tests
rake test_tags                # Tag system tests
rake test_integration         # Integration tests
rake test_performance         # Performance benchmarks

# Services & Setup
rake check_services           # Verify Docker services
rake check_gems               # Check dependencies
rake download_test_images     # Download test images

# Code Quality
rake rubocop                  # Style check
rake rubocop_fix              # Auto-fix style issues
rake reek                     # Code smells
rake bundler_audit            # Security audit

# Build & Install
rake install_local            # Build and install gem
rake build                    # Build gem package
```

### Docker Services

```bash
# Start test services
docker-compose -f docker-compose.test.yml --env-file .env.test up -d

# Check service status
rake check_services

# Stop services  
docker-compose -f docker-compose.test.yml down
```

---

**Related Documents:**

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed component architecture
- [testing.md](testing.md) - Comprehensive testing guide
- [providers.md](providers.md) - Provider comparison and setup
- [picture_tag_migration.md](picture_tag_migration.md) - Picture Tag migration
- [PARALLEL_TESTING.md](PARALLEL_TESTING.md) - Parallel testing setup
- [scripts.md](scripts.md) - Development scripts and utilities
