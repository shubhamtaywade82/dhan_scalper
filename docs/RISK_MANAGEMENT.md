# Risk Management Configuration

The DhanScalper trading system includes comprehensive risk management features to protect capital and manage trading exposure.

## Overview

The `UnifiedRiskManager` consolidates all risk management logic into a single, robust system that includes:

- **Time Stops**: Automatic position closure after a specified time
- **Daily Loss Cap**: Session-wide loss limit protection
- **Cooldown Periods**: Temporary trading halt after losses
- **Idempotency Protection**: Prevents duplicate exit orders
- **Take Profit & Stop Loss**: Traditional risk management
- **Trailing Stops**: Dynamic stop loss adjustment

## Configuration

### Basic Risk Parameters

```yaml
global:
  # Take Profit: Close position when profit reaches this percentage
  tp_pct: 0.35  # 35% profit target

  # Stop Loss: Close position when loss reaches this percentage
  sl_pct: 0.18  # 18% stop loss

  # Trailing Stop: Adjust stop loss when profit reaches this percentage
  trail_pct: 0.12  # 12% trailing stop trigger

  # Risk check interval (seconds)
  risk_check_interval: 1
```

### Enhanced Risk Management

```yaml
global:
  # Time Stop: Close position after specified time (seconds)
  time_stop_seconds: 300  # 5 minutes
  enable_time_stop: true

  # Daily Loss Cap: Maximum session loss (₹)
  max_daily_loss_rs: 2000.0  # ₹2,000 maximum daily loss
  enable_daily_loss_cap: true

  # Cooldown: Pause trading after a loss (seconds)
  cooldown_after_loss_seconds: 180  # 3 minutes
  enable_cooldown: true
```

## Risk Management Features

### 1. Time Stops

**Purpose**: Prevents positions from being held too long, reducing overnight risk.

**Configuration**:
- `time_stop_seconds`: Maximum time a position can be held (default: 300 seconds)
- `enable_time_stop`: Enable/disable time stops (default: true)

**Behavior**:
- Tracks entry time for each position
- Automatically closes position when time limit is reached
- Triggers with reason "TIME_STOP"

### 2. Daily Loss Cap

**Purpose**: Protects against catastrophic daily losses by closing all positions.

**Configuration**:
- `max_daily_loss_rs`: Maximum allowed daily loss in ₹ (default: ₹2,000)
- `enable_daily_loss_cap`: Enable/disable daily loss cap (default: true)

**Behavior**:
- Tracks session starting equity
- Calculates current drawdown
- Closes ALL positions when daily loss cap is exceeded
- Triggers with reason "DAILY_LOSS_CAP"

### 3. Cooldown Periods

**Purpose**: Prevents emotional trading after losses by temporarily halting new position checks.

**Configuration**:
- `cooldown_after_loss_seconds`: Cooldown duration in seconds (default: 180)
- `enable_cooldown`: Enable/disable cooldown (default: true)

**Behavior**:
- Activates after any position is closed at a loss
- Prevents new position risk checks during cooldown
- Emergency exits (daily loss cap) still function
- Automatically expires after specified time

### 4. Idempotency Protection

**Purpose**: Prevents duplicate exit orders when multiple triggers fire simultaneously.

**Implementation**:
- Generates unique idempotency keys for each exit attempt
- Tracks pending exits to prevent duplicates
- Uses format: `risk_exit_{security_id}_{reason}_{timestamp}_{random}`

**Behavior**:
- If an exit is already pending/completed, subsequent attempts are ignored
- Prevents multiple sell orders for the same position
- Logs duplicate attempts for monitoring

### 5. Traditional Risk Management

#### Take Profit
- Closes position when profit reaches configured percentage
- Calculated as: `(current_price - entry_price) / entry_price >= tp_pct`

#### Stop Loss
- Closes position when loss reaches configured percentage
- Calculated as: `(entry_price - current_price) / entry_price >= sl_pct`

#### Trailing Stop
- Adjusts stop loss upward as position moves in favor
- Only triggers after position has moved up from entry
- Calculated as: `current_price < (position_high - trail_pct * position_high)`

## Risk Priority Order

The risk manager checks conditions in the following priority:

1. **Daily Loss Cap** (Highest Priority)
   - Emergency exit for all positions
   - Overrides all other conditions

2. **Cooldown Check**
   - Skips individual position checks if in cooldown
   - Emergency exits still function

3. **Individual Position Checks** (in order):
   - Take Profit
   - Stop Loss
   - Time Stop
   - Trailing Stop

## Logging and Monitoring

The risk manager provides comprehensive logging:

```
[2025-09-12 20:58:25] INFO  -- : RiskManager: Starting unified risk management loop (interval: 1s)
[2025-09-12 20:58:25] INFO  -- : RiskManager: Time stop: 300s
[2025-09-12 20:58:25] INFO  -- : RiskManager: Daily loss cap: ₹2000.0
[2025-09-12 20:58:25] INFO  -- : RiskManager: Cooldown: 180s
[2025-09-12 20:58:25] INFO  -- : RiskManager: Exiting position 12345 reason: TAKE_PROFIT LTP: ₹150.25
[2025-09-12 20:58:25] WARN  -- : RiskManager: Daily loss cap exceeded! Drawdown: ₹2500.0 (max: ₹2000.0)
[2025-09-12 20:58:25] INFO  -- : RiskManager: Loss detected, starting cooldown period
```

## Best Practices

### Configuration Recommendations

1. **Conservative Settings** (New Traders):
   ```yaml
   tp_pct: 0.25
   sl_pct: 0.15
   time_stop_seconds: 180
   max_daily_loss_rs: 1000.0
   cooldown_after_loss_seconds: 300
   ```

2. **Aggressive Settings** (Experienced Traders):
   ```yaml
   tp_pct: 0.50
   sl_pct: 0.25
   time_stop_seconds: 600
   max_daily_loss_rs: 5000.0
   cooldown_after_loss_seconds: 60
   ```

3. **Scalping Settings** (High Frequency):
   ```yaml
   tp_pct: 0.15
   sl_pct: 0.10
   time_stop_seconds: 60
   max_daily_loss_rs: 500.0
   cooldown_after_loss_seconds: 30
   ```

### Monitoring Recommendations

1. **Monitor Risk Logs**: Watch for frequent cooldown activations
2. **Track Daily Losses**: Ensure daily loss cap is appropriate
3. **Review Time Stops**: Adjust based on market conditions
4. **Check Idempotency**: Verify no duplicate orders in logs

## Troubleshooting

### Common Issues

1. **Positions Not Closing**:
   - Check if cooldown is active
   - Verify risk parameters are appropriate
   - Ensure broker connectivity

2. **Frequent Cooldowns**:
   - Consider adjusting stop loss percentage
   - Review market volatility
   - Check position sizing

3. **Daily Loss Cap Triggering**:
   - Review position sizing
   - Consider adjusting loss cap
   - Check for market gaps

### Debug Mode

Enable debug logging to see detailed risk calculations:

```ruby
DhanScalper::Support::Logger.setup(level: :debug)
```

This will show detailed risk calculations and decision-making process.
