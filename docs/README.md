# ImgFlow Documentation

Welcome to the ImgFlow documentation! This guide will help you get started with using ImgFlow for image optimization in your Jekyll sites.

## 🚀 Quick Start

1. [Installation Guide](installation.md) - How to install and configure ImgFlow
2. [Basic Usage](usage/) - Core functionality and examples
3. [Testing](testing.md) - How to run and write tests

## 📚 Documentation Index

### 🛠️ Setup & Configuration

- **[Installation Guide](installation.md)** - Installation and basic setup
- **[Docker Setup](docker.md)** - Using ImgFlow with Docker
- **[Provider Configuration](providers.md)** - Configuring image providers

### 📖 Usage & Features

- **[Tags Reference](usage/tags.md)** - Available Jekyll tags
- **[Presets System](usage/presets.md)** - Using image presets
- **[Preset Examples](usage/preset-examples.md)** - Practical preset examples
- **[Jekyll Picture Tag Migration](picture_tag_migration.md)** - Migrate from Picture Tag to ImgFlow

### 🧪 Testing

- **[Testing Guide](testing.md)** - Running and writing tests
- **[Parallel Testing](parallel_testing.md)** - Parallel testing setup and usage
- **[Scripts Reference](scripts.md)** - Development scripts and utilities

### 💻 Development

- **[Development Guide](development.md)** - Contributing and development setup
- **[Architecture Guide](ARCHITECTURE.md)** - Component architecture and data flow

### ⚡ Performance

- **[Performance Testing](performance/)** - Performance benchmarks and results
- **[Performance Template](template/performance.md)** - Performance report template

## 📝 Documentation System

ImgFlow maintains a **structured documentation system** to ensure consistency and maintainability:

### 📁 Documentation Structure

**Main Documentation:**

- 📝 **Root docs** - Core guides and references
- 📚 **Template files** - Reusable content templates in `docs/template/`
- 🔄 **Usage guides** - Organized by functionality in `docs/usage/`

### 🛠️ Working with Documentation

When updating documentation:

1. **Edit the appropriate file** in the docs hierarchy
2. **Check for related content** in template files if needed
3. **Review links** and cross-references
4. **Test changes** by verifying all links work

### 🎯 Benefits

- ✅ **Organized structure** - Logical grouping by topic
- ✅ **Easy navigation** - Clear hierarchy and cross-links
- ✅ **Maintainable** - Single location for each topic
- ✅ **User-friendly** - Quick access to relevant information

## 🔧 Quick Reference

### Essential Commands

```bash
# Development
bundle exec jekyll serve              # Start development server
bundle exec jekyll build              # Build site

# Testing
rake quick                           # Quick checks (style + tests)
rake test                            # All tests
rake parallel:test                   # Parallel testing (faster)

# Docker Services
docker-compose -f docker-compose.test.yml up -d  # Start services
rake check_services                  # Verify services
```

### Key Files

- **`lib/jekyll-imgflow.rb`** - Main module
- **`lib/jekyll-imgflow/imgflow_tag.rb`** - Main tag implementation
- **`lib/jekyll-imgflow/html_generator.rb`** - HTML generation
- **`lib/jekyll-imgflow/picture_tag_adaptor.rb`** - Picture Tag compatibility

### Development Scripts

```bash
# Debugging
ruby scripts/debug_picture_tag.rb      # Test Picture Tag adaptor
ruby scripts/debug_test_url.rb         # Test URL handling

# Testing
ruby scripts/performance_benchmark.rb # Run performance tests
ruby scripts/test_logger.rb status    # Show test status

# Migration
bin/imgflow_migrate_presets --preview  # Preview preset migration
bin/imgflow_migrate_presets            # Migrate presets
```

## 🏗️ Architecture

**See:** [ARCHITECTURE.md](ARCHITECTURE.md) for detailed component architecture and data flow

ImgFlow consists of several key components:

- **Providers** - Image processing backends (CLI tools, HTTP APIs)
- **Tags** - Jekyll template tags for image optimization
- **Presets** - Predefined image processing configurations
- **Parser** - Input validation and markup parsing
- **HTML Generator** - Unified HTML output generation
- **Picture Tag Adaptor** - Jekyll Picture Tag compatibility

### Processing Flows

1. **Build-Time** - Pre-generate images during Jekyll build
2. **Runtime** - Process images on-demand during template rendering

## 🤝 Contributing

See the [Development Guide](development.md) for information on contributing to ImgFlow.

**Important:** When updating documentation:

1. Edit the appropriate documentation file
2. Review and test all links
3. Update cross-references if needed

## 📄 License

This project is licensed under the AGPL-3.0-or-later License - see the [LICENSE](../LICENSE) file for details.

---

**Back to:** [Main README](../README.md) | **Top:** [Documentation Index](#documentation-index)
