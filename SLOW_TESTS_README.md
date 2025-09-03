# Slow Tests Configuration

This document describes the slow test tagging system implemented for DhanScalper.

## Overview

Slow tests have been tagged with `:slow` to allow selective running of test suites. This improves development workflow by allowing fast feedback during development while still enabling comprehensive testing when needed.

## Tagged Tests

### Integration Tests (Always Slow)
- `spec/integration/csv_master_integration_spec.rb` - Loads large CSV datasets (175,009 records)
- `spec/integration/dhan_scalper_integration_spec.rb` - Full system integration tests

### Performance Tests
- `spec/csv_master_spec.rb` - Performance considerations section
- `spec/ui/dashboard_spec.rb` - Performance considerations and integration tests
- `spec/ui/data_viewer_spec.rb` - Integration tests for signal handling, cursor management, and data refresh

## Usage

### Run Fast Tests Only (Default)
```bash
bundle exec rspec
# or
bin/test
```

### Run All Tests Including Slow Ones
```bash
RUN_SLOW_TESTS=1 bundle exec rspec
# or
bin/test --slow
```

### Run Only Slow Tests
```bash
bundle exec rspec --tag slow
```

### Run Only Integration Tests
```bash
bundle exec rspec spec/integration/
# or
bin/test --integration
```

### Run Only Unit Tests
```bash
bundle exec rspec --tag '~slow' --exclude-pattern 'spec/integration/**/*_spec.rb'
# or
bin/test --unit
```

## Configuration

The slow test filtering is configured in `spec/spec_helper.rb`:

```ruby
# Configure slow tests
config.filter_run_excluding :slow unless ENV["RUN_SLOW_TESTS"]
```

## Test Runner Script

A convenience script `bin/test` has been created with the following options:

- `--slow` - Include slow tests
- `--integration` - Run integration tests only
- `--unit` - Run unit tests only
- `--help` - Show help message

## Benefits

1. **Faster Development**: Quick feedback during development with fast tests only
2. **Comprehensive Testing**: Full test suite including slow tests when needed
3. **CI/CD Flexibility**: Can run different test suites in different environments
4. **Selective Testing**: Run specific types of tests based on what you're working on

## Examples

```bash
# Quick development feedback
bundle exec rspec

# Full test suite before commit
RUN_SLOW_TESTS=1 bundle exec rspec

# Test only CSV functionality
bundle exec rspec spec/csv_master_spec.rb

# Test only slow CSV performance tests
bundle exec rspec spec/csv_master_spec.rb --tag slow
```
