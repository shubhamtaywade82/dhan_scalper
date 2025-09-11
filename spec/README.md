# DhanScalper Test Suite

This directory contains a comprehensive test suite for the DhanScalper paper trading system, organized into multiple categories to ensure thorough coverage and maintainability.

## 📁 Test Structure

```
spec/
├── unit/                          # Unit tests for individual components
│   ├── enhanced_paper_app_spec.rb
│   └── advanced_indicators_spec.rb
├── integration/                   # Integration tests for component interactions
│   └── paper_trading_workflow_spec.rb
├── end_to_end/                    # End-to-end tests for complete workflows
│   └── complete_trading_session_spec.rb
├── performance/                   # Performance and load tests
│   └── high_frequency_trading_spec.rb
├── support/                       # Test utilities and helpers
│   ├── test_helpers.rb
│   ├── integration_helpers.rb
│   └── advanced_test_helpers.rb
├── fixtures/                      # Test data and fixtures
│   └── test_data.rb
└── run_comprehensive_test_suite.rb # Test runner script
```

## 🧪 Test Categories

### Unit Tests (`spec/unit/`)
- **Purpose**: Test individual components in isolation
- **Coverage**: Core classes, methods, and edge cases
- **Examples**:
  - `DhanScalper::PaperApp` initialization and configuration
  - `DhanScalper::Indicators::HolyGrail` signal generation
  - `DhanScalper::CandleSeries` technical analysis methods
- **Characteristics**: Fast execution, extensive mocking, edge case coverage

### Integration Tests (`spec/integration/`)
- **Purpose**: Test component interactions and data flow
- **Coverage**: Service integration, data flow, realistic scenarios
- **Examples**:
  - Paper trading workflow with multiple symbols
  - Position management across components
  - Risk management integration
- **Characteristics**: Moderate execution time, realistic data, component interaction

### End-to-End Tests (`spec/end_to_end/`)
- **Purpose**: Test complete trading workflows
- **Coverage**: Full system simulation, realistic market conditions
- **Examples**:
  - Complete trading session simulation
  - Market scenario testing (bullish, bearish, volatile)
  - Session reporting and data persistence
- **Characteristics**: Longer execution time, full system simulation, realistic data

### Performance Tests (`spec/performance/`)
- **Purpose**: Test system performance and scalability
- **Coverage**: High-frequency trading, memory management, CPU usage
- **Examples**:
  - High-frequency signal analysis (1-second intervals)
  - Concurrent trading operations
  - Memory efficiency during long sessions
  - Network latency handling
- **Characteristics**: Performance-focused, stress testing, resource monitoring

## 🚀 Running Tests

### Quick Start
```bash
# Run all tests
bundle exec rspec

# Run specific category
bundle exec rspec spec/unit/
bundle exec rspec spec/integration/
bundle exec rspec spec/end_to_end/
bundle exec rspec spec/performance/

# Run with comprehensive reporting
ruby spec/run_comprehensive_test_suite.rb
```

### Advanced Usage
```bash
# Run only unit tests
ruby spec/run_comprehensive_test_suite.rb --unit

# Run integration and e2e tests
ruby spec/run_comprehensive_test_suite.rb --integration --e2e

# Run all tests with detailed output
bundle exec rspec --format documentation

# Run specific test file
bundle exec rspec spec/unit/enhanced_paper_app_spec.rb

# Run tests with performance monitoring
RUN_SLOW_TESTS=true bundle exec rspec spec/performance/
```

## 📊 Test Coverage

The test suite aims for comprehensive coverage across:

- **Code Coverage**: >90% (enforced by SimpleCov)
- **Component Coverage**: All major classes and modules
- **Scenario Coverage**: Bullish, bearish, neutral, and volatile markets
- **Edge Case Coverage**: Error conditions, boundary values, failure modes
- **Performance Coverage**: High-frequency, memory, CPU, and network scenarios

## 🛠️ Test Utilities

### MockFactory
Advanced mock creation for complex scenarios:
```ruby
# Create realistic market data
market_data = MockFactory.create_realistic_market_data(
  symbols: ["NIFTY", "BANKNIFTY"],
  periods: 200
)

# Create realistic positions
positions = MockFactory.create_realistic_positions(count: 10)

# Create session statistics
stats = MockFactory.create_realistic_session_stats
```

### PerformanceMonitor
Performance testing utilities:
```ruby
monitor = PerformanceMonitor.new
monitor.start

# Run operation
operation.call

monitor.stop
puts "Duration: #{monitor.duration}s"
puts "Memory: #{monitor.memory_usage}KB"
```

### MarketSimulator
Realistic market condition simulation:
```ruby
simulator = MarketSimulator.new(symbols: ["NIFTY"], volatility: 0.15)
simulator.set_trend("NIFTY", :bullish)
price = simulator.simulate_price_movement("NIFTY")
```

### ConcurrentTestRunner
Concurrent testing utilities:
```ruby
results = ConcurrentTestRunner.run_concurrent_operations(100) do |thread_id, op_id|
  # Test operation
end
```

## 📈 Performance Benchmarks

### Expected Performance Targets
- **Unit Tests**: <5 seconds total
- **Integration Tests**: <30 seconds total
- **End-to-End Tests**: <2 minutes total
- **Performance Tests**: <5 minutes total

### Memory Usage Targets
- **Unit Tests**: <50MB peak
- **Integration Tests**: <100MB peak
- **End-to-End Tests**: <200MB peak
- **Performance Tests**: <500MB peak

### High-Frequency Trading Targets
- **Signal Analysis**: <20ms per iteration
- **Position Management**: <10ms per position
- **Order Execution**: <5ms per order
- **Memory Growth**: <1MB per 1000 iterations

## 🔧 Configuration

### Test Environment Variables
```bash
# Enable slow tests
export RUN_SLOW_TESTS=true

# Enable verbose test output
export VERBOSE_TESTS=true

# Set test timeout
export TEST_TIMEOUT=300

# Enable performance monitoring
export MONITOR_PERFORMANCE=true
```

### RSpec Configuration
The test suite uses RSpec with the following configuration:
- **Format**: Documentation for human-readable output
- **Color**: Enabled for better readability
- **Coverage**: SimpleCov with 90% minimum coverage
- **Mocking**: WebMock for HTTP requests
- **Helpers**: Custom test helpers for complex scenarios

## 🐛 Debugging Tests

### Common Issues
1. **Slow Tests**: Use `RUN_SLOW_TESTS=true` to enable performance tests
2. **Memory Issues**: Check for memory leaks in long-running tests
3. **Flaky Tests**: Review timing-dependent assertions
4. **Mock Issues**: Verify mock setup and expectations

### Debug Commands
```bash
# Run single test with debug output
bundle exec rspec spec/unit/enhanced_paper_app_spec.rb --format documentation

# Run with backtrace
bundle exec rspec --backtrace

# Run specific test case
bundle exec rspec spec/unit/enhanced_paper_app_spec.rb:142

# Run with coverage report
COVERAGE=true bundle exec rspec
```

## 📝 Writing New Tests

### Unit Test Template
```ruby
RSpec.describe DhanScalper::ComponentName, :unit do
  let(:component) { described_class.new(params) }

  describe "#method_name" do
    context "with valid input" do
      it "returns expected result" do
        expect(component.method_name(input)).to eq(expected)
      end
    end

    context "with invalid input" do
      it "handles error gracefully" do
        expect { component.method_name(invalid_input) }.not_to raise_error
      end
    end
  end
end
```

### Integration Test Template
```ruby
RSpec.describe "Component Integration", :integration do
  before do
    setup_integration_mocks
  end

  it "integrates components correctly" do
    # Test component interaction
  end
end
```

### Performance Test Template
```ruby
RSpec.describe "Performance Test", :performance, :slow do
  it "meets performance requirements" do
    start_time = Time.now

    # Run performance-critical operation
    operation.call

    duration = Time.now - start_time
    expect(duration).to be < max_duration
  end
end
```

## 🎯 Best Practices

### Test Organization
- Group related tests in `describe` blocks
- Use `context` for different scenarios
- Use descriptive test names
- Keep tests focused and atomic

### Mocking Strategy
- Mock external dependencies
- Use realistic test data
- Verify mock interactions
- Clean up after tests

### Performance Testing
- Set realistic performance targets
- Monitor memory usage
- Test under load
- Measure and track improvements

### Error Testing
- Test error conditions
- Verify error handling
- Test edge cases
- Ensure graceful degradation

## 📚 Additional Resources

- [RSpec Documentation](https://rspec.info/)
- [SimpleCov Documentation](https://github.com/simplecov-ruby/simplecov)
- [WebMock Documentation](https://github.com/bblimke/webmock)
- [Concurrent Ruby Documentation](https://github.com/ruby-concurrency/concurrent-ruby)

## 🤝 Contributing

When adding new tests:
1. Follow the existing test structure
2. Add appropriate test categories
3. Include both positive and negative test cases
4. Add performance tests for critical paths
5. Update this README if adding new test utilities
6. Ensure all tests pass before submitting

## 📊 Test Metrics

The test suite provides comprehensive metrics:
- **Execution Time**: Per category and overall
- **Memory Usage**: Peak and average consumption
- **Coverage**: Line, branch, and method coverage
- **Performance**: Throughput and latency measurements
- **Reliability**: Success rate and flakiness detection

Use these metrics to identify performance bottlenecks, coverage gaps, and areas for improvement.
