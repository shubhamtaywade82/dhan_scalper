# Risk Management Migration Guide

This guide helps you migrate from the old risk management system to the new `UnifiedRiskManager`.

## What Changed

### Before (Old System)
- **Two separate risk managers**: `RiskManager` and `EnhancedRiskManager`
- **No idempotency protection**: Risk of duplicate exit orders
- **Limited documentation**: Hard to understand configuration
- **Inconsistent logging**: Mixed logging approaches

### After (Unified System)
- **Single unified risk manager**: `UnifiedRiskManager` consolidates all features
- **Idempotency protection**: Prevents duplicate exit orders
- **Comprehensive documentation**: Complete setup and configuration guide
- **Structured logging**: Consistent, component-based logging

## Migration Steps

### 1. Update Application Code

**Old Code:**
```ruby
# Using old RiskManager
@risk_manager = RiskManager.new(@config, @position_tracker, @broker, logger: @logger)

# Or using EnhancedRiskManager
@risk_manager = EnhancedRiskManager.new(
  @config,
  @position_tracker,
  @broker,
  @balance_provider,
  @equity_calculator,
  logger: @logger
)
```

**New Code:**
```ruby
# Using UnifiedRiskManager
@risk_manager = UnifiedRiskManager.new(
  @config,
  @position_tracker,
  @broker,
  balance_provider: @balance_provider,
  equity_calculator: @equity_calculator,
  logger: @logger
)
```

### 2. Update Configuration

**Add to your `scalper.yml`:**
```yaml
global:
  # Existing risk parameters
  tp_pct: 0.35
  sl_pct: 0.18
  trail_pct: 0.12

  # New enhanced risk management
  time_stop_seconds: 300
  enable_time_stop: true
  max_daily_loss_rs: 2000.0
  enable_daily_loss_cap: true
  cooldown_after_loss_seconds: 180
  enable_cooldown: true
```

### 3. Update Imports

**Old:**
```ruby
require_relative "risk_manager"
# or
require_relative "enhanced_risk_manager"
```

**New:**
```ruby
require_relative "unified_risk_manager"
```

## Feature Comparison

| Feature                     | Old RiskManager | EnhancedRiskManager | UnifiedRiskManager |
| --------------------------- | --------------- | ------------------- | ------------------ |
| Take Profit                 | ✅               | ✅                   | ✅                  |
| Stop Loss                   | ✅               | ✅                   | ✅                  |
| Trailing Stop               | ✅               | ✅                   | ✅                  |
| Time Stops                  | ❌               | ✅                   | ✅                  |
| Daily Loss Cap              | ❌               | ✅                   | ✅                  |
| Cooldown Periods            | ❌               | ✅                   | ✅                  |
| Idempotency Protection      | ❌               | ✅                   | ✅                  |
| Structured Logging          | ❌               | ❌                   | ✅                  |
| Comprehensive Documentation | ❌               | ❌                   | ✅                  |

## New Features

### 1. Idempotency Protection
Prevents duplicate exit orders when multiple triggers fire simultaneously.

**Example:**
```ruby
# If both trailing stop and time stop trigger at the same time,
# only one exit order will be placed
risk_manager.execute_exit(position, "SEC123", 150.0, "TRAILING_STOP")
risk_manager.execute_exit(position, "SEC123", 150.0, "TIME_STOP") # Ignored
```

### 2. Enhanced Logging
Structured logging with component identification and timestamps.

**Example:**
```
[2025-09-12 20:58:25] INFO  -- : RiskManager: Exiting position SEC123 reason: TAKE_PROFIT LTP: ₹150.25
[2025-09-12 20:58:25] WARN  -- : RiskManager: Daily loss cap exceeded! Drawdown: ₹2500.0 (max: ₹2000.0)
```

### 3. Comprehensive Configuration
All risk management features are configurable through YAML.

**Example:**
```yaml
global:
  # Basic risk management
  tp_pct: 0.35
  sl_pct: 0.18
  trail_pct: 0.12

  # Enhanced features
  time_stop_seconds: 300
  max_daily_loss_rs: 2000.0
  cooldown_after_loss_seconds: 180

  # Feature toggles
  enable_time_stop: true
  enable_daily_loss_cap: true
  enable_cooldown: true
```

## Backward Compatibility

The `UnifiedRiskManager` is designed to be backward compatible with existing configurations. If you don't specify the new parameters, it will use sensible defaults:

- `time_stop_seconds`: 300 (5 minutes)
- `max_daily_loss_rs`: ₹2,000
- `cooldown_after_loss_seconds`: 180 (3 minutes)
- All features enabled by default

## Testing Your Migration

### 1. Test Configuration Loading
```ruby
require 'dhan_scalper'

config = YAML.load_file('config/scalper.yml')
risk_manager = DhanScalper::UnifiedRiskManager.new(
  config,
  position_tracker,
  broker,
  balance_provider: balance_provider,
  equity_calculator: equity_calculator
)

puts "Risk manager loaded successfully!"
```

### 2. Test Risk Calculations
```ruby
# Test take profit calculation
entry_price = 100.0
current_price = 140.0  # 40% profit
tp_pct = 0.35  # 35% target

profit_pct = (current_price - entry_price) / entry_price
should_tp = profit_pct >= tp_pct

puts "Should take profit: #{should_tp}"
```

### 3. Test Idempotency
```ruby
# Generate idempotency keys
key1 = risk_manager.send(:generate_idempotency_key, "TEST123", "TAKE_PROFIT")
key2 = risk_manager.send(:generate_idempotency_key, "TEST123", "TAKE_PROFIT")

puts "Keys are different: #{key1 != key2}"
```

## Troubleshooting

### Common Issues

1. **Import Errors**
   - Make sure to update all `require_relative` statements
   - Check that `unified_risk_manager.rb` is in the correct location

2. **Configuration Errors**
   - Verify YAML syntax is correct
   - Check that all required parameters are present

3. **Logging Issues**
   - Ensure logger is properly initialized
   - Check log level settings

### Getting Help

If you encounter issues during migration:

1. Check the logs for error messages
2. Verify your configuration matches the examples
3. Test with a simple configuration first
4. Review the comprehensive documentation in `docs/RISK_MANAGEMENT.md`

## Benefits of Migration

- **Reduced Complexity**: Single risk manager instead of two
- **Better Reliability**: Idempotency protection prevents duplicate orders
- **Enhanced Monitoring**: Structured logging for better debugging
- **Future-Proof**: All new features will be added to the unified manager
- **Better Documentation**: Comprehensive guides and examples

## Next Steps

After migration:

1. **Review Configuration**: Ensure all risk parameters are appropriate for your strategy
2. **Monitor Logs**: Watch for any issues during initial runs
3. **Test Thoroughly**: Run in paper mode before live trading
4. **Optimize Settings**: Adjust parameters based on your trading results

The unified risk management system provides a solid foundation for safe and reliable trading operations! 🚀
