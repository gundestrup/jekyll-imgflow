# Parallel Testing - Quick Guide

## Overview

ImgFlow supports parallel testing for faster execution.

## How It Works

- **Auto-detects CPU cores** (uses n-1 cores, max 8)
- **Pre-builds test sites** for optimal performance
- **Runs tests in parallel** on different ports

## Running Tests

### Single Test (Port 4000)

```bash
bundle exec rspec spec/imgflow_system_spec.rb
```

### Parallel Tests (Ports 4010-4016)

```bash
bundle exec rspec  # Auto-detects and runs in parallel
```

### Provider Testing

```bash
# Test all providers in parallel
bundle exec rspec spec/provider_interface_spec.rb

# Test specific provider
TEST_PROVIDER=sharp bundle exec rspec spec/provider_interface_spec.rb
```

## Port Assignment

| Process | Port | TEST_ENV_NUMBER |
|---------|------|-----------------|
| Process 0 | 4010 | "" |
| Process 1 | 4011 | "1" |
| Process 2 | 4012 | "2" |
| ... | ... | ... |

## Performance

- **Speedup**: Up to 7x faster
- **Resource limit**: Max 8 parallel processes
- **Memory**: Pre-builds test sites to reduce overhead

## Troubleshooting

### Port Conflicts

```bash
# Kill processes on test ports
lsof -ti:4010-4016 | xargs kill -9
```

### Resource Issues

- Reduce parallel processes if system is slow
- Use `PARALLEL_TEST_PROCESSORS=4` to limit processes

### Gem Issues

```bash
# Install parallel gem
bundle add parallel
```

## Files

- `spec/support/parallel_provider_test_helper.rb` - Parallel test helper
- `Gemfile` - Contains `parallel` gem dependency

## Status

✅ **Ready** - All tests support parallel execution
