# Changelog


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
