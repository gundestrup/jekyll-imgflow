# ImgFlow Development Guide

## Quick Start

```bash
bundle install        # Install dependencies
rake quick            # Style + tests (fastest)
rake                  # Full quality checks
```

## Architecture

**See:** [ARCHITECTURE.md](ARCHITECTURE.md) for the full file tree, component
architecture, and data flow. Key points:

- **Two processing flows:** Build-Time (pre-generate defaults) and Runtime (on-demand)
- **Providers:** Image processing backends (CLI tools and HTTP APIs)
- **Tags:** Jekyll template tags for image optimization

## Development Workflow

1. Edit code in `lib/` directory
2. Test changes quickly: `rake quick`
3. Run the CI-equivalent checks before pushing: `rake ci`
4. Commit and push; the pre-push hook runs `rake ci` automatically
5. Run the full quality suite when needed: `rake`

`rake ci` runs RuboCop and `bundle exec rspec --tag ~slow`, matching the
GitHub Actions workflow. It includes external tests that can run with local
CLI providers. Docker-backed HTTP provider tests remain local-only and should
be run with the test services started.

Install or refresh the Git hooks with `bin/install-hooks.sh`. The pre-commit
hook runs RuboCop; the pre-push hook runs the CI-equivalent checks and, for
release tags, verifies Docker image pins.

**Commands:** See [rake.md](rake.md) for the full Rake task reference.

## Testing

**See:** [testing.md](testing.md) for the comprehensive testing guide and
[parallel_testing.md](parallel_testing.md) for parallel test execution.

```bash
bundle exec rspec              # All tests
bundle exec rspec --parallel   # Parallel execution
rake parallel:test             # Parallel testing via Rake
```

## Docker Services

**See:** [docker.md](docker.md) for Docker service configuration, ports, and troubleshooting.

```bash
rake start_services           # Start services (pulls latest pinned images)
rake check_services           # Verify services are running
rake stop_services            # Stop services
```

## Adding Dependencies

The project follows the [rubygems guide](https://github.com/rubygems/guides/blob/main/gemfile-and-gemspec.md)
for dependency management:

- **Runtime dependencies** (gems needed by users of the gem) go in the
  **gemspec** (`s.add_dependency`). Keep version constraints wide (e.g.
  `>= 4.0`) so the gem coexists with other gems in a user's application.
- **Development dependencies** (gems needed only to develop/test the gem)
  go in the **Gemfile** `:development` group, never in the gemspec. The
  Gemfile uses the `gemspec` directive to pull runtime deps automatically,
  so there is no duplication.

```bash
# Add a runtime dependency (edit gemspec, then bundle install)
#   s.add_dependency "new_gem", "~> 1.0"

# Add a development dependency (edit Gemfile, then bundle install)
bundle add new_gem --group development
```

## Adding New Providers

1. Create provider class in `lib/jekyll-imgflow/providers/`
2. Inherit from `BaseProvider`
3. Implement required methods: `resize`, `crop`, etc.
4. Add to `provider_registry.rb`
5. Add tests
6. Update Docker services if HTTP API

**See:** [providers.md](providers.md) for provider comparison and setup.

## Picture Tag Migration

See [picture_tag_migration.md](picture_tag_migration.md) for the complete migration guide.

## Release Process

See the [AGENTS.md Release Process](../AGENTS.md#release-process) section for the
authoritative release procedure. In short: bump version with `rake version:bump`,
add a CHANGELOG entry, commit, tag `v*`, and push — the GitHub Actions workflow
handles building and publishing to RubyGems via OIDC trusted publishing.

## Troubleshooting

### Tests Failing

```bash
bundle install      # Update dependencies
rm -rf tmp/         # Clear cache
./create-test-images.sh  # Refresh test images
```

### Docker Issues

See [docker.md](docker.md#troubleshooting) for Docker troubleshooting.

## Scripts

- `create-test-images.sh` - Download test images
- `bin/install-hooks.sh` - Install git hooks (pre-commit: rubocop, pre-push: rubocop + rspec)

**See:** [scripts.md](scripts.md) for the full scripts reference.

## Configuration Files

- **`Gemfile`** - Development dependencies and Jekyll version pin. Uses the `gemspec` directive to pull runtime dependencies from the gemspec automatically. Development dependencies are declared here (not in the gemspec) to avoid version drift — see the [rubygems guide](https://github.com/rubygems/guides/blob/main/gemfile-and-gemspec.md).
- **`jekyll-imgflow.gemspec`** - Gem manifest: metadata, runtime dependencies (`benchmark`, `fastimage`, `jekyll`), and packaged files. Development dependencies are intentionally not declared here.
- **`Rakefile`** - Build and test tasks (see [rake.md](rake.md))
- **`.env.test`** - Test environment variables
