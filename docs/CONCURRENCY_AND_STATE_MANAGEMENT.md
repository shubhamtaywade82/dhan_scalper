# Concurrency and State Management

This document describes the comprehensive concurrency and state management improvements implemented in DhanScalper to address race conditions and ensure data consistency.

## Overview

The original system had several critical concurrency issues:

1. **No atomic updates**: Balance and position updates directly modified in-memory variables without locks
2. **Race conditions**: Concurrent operations could lead to inconsistent state
3. **Busy loops**: Single-threaded loops with sleep wasted resources and could miss events
4. **No transaction safety**: Multiple operations weren't atomic

## Solutions Implemented

### 1. Atomic State Management

#### `AtomicStateManager`
- **Redis-based transactions** ensure atomic updates
- **Mutex protection** for critical sections
- **State validation** before and after updates
- **Consistent snapshots** for read operations

```ruby
# Atomic balance update
state_manager.atomic_balance_update("debit") do |state|
  state[:available] = Money.subtract(state[:available], amount)
  state[:used] = Money.add(state[:used], amount)
  state[:total] = Money.add(state[:available], state[:used])
  state
end
```

#### `AtomicPaperWallet`
- **Thread-safe balance operations** using atomic state manager
- **Consistent state** across all operations
- **Validation** before each operation
- **Error handling** with proper exceptions

### 2. Event-Driven Architecture

#### `EventDrivenScheduler`
- **Async task scheduling** replaces busy loops
- **Concurrent execution** of multiple tasks
- **Resource efficient** - no CPU waste on sleep
- **Flexible scheduling** - recurring, one-time, delayed tasks

```ruby
# Schedule recurring task
scheduler.schedule_recurring("trading_loop", 60) do
  execute_trading_cycle
end

# Schedule one-time task
scheduler.schedule_once("cleanup", 300) do
  cleanup_resources
end
```

#### `EventDrivenApp`
- **Event-driven main loop** instead of busy loops
- **Concurrent task execution** for different operations
- **Graceful shutdown** handling
- **Resource management** with proper cleanup

### 3. Concurrent Processing

#### Task Scheduling
- **Trading decisions**: Scheduled at configurable intervals
- **Risk management**: Continuous monitoring with proper intervals
- **Status reporting**: Regular updates without blocking
- **Market data**: Concurrent updates for multiple symbols

#### Thread Safety
- **Atomic operations** prevent race conditions
- **Mutex protection** for critical sections
- **Consistent state** across all threads
- **Error isolation** between concurrent tasks

## Architecture Comparison

### Before (Problematic)
```
Main Thread:
├── while true
│   ├── sleep(1)
│   ├── check_risk()      # Race condition
│   ├── update_balance()  # Not atomic
│   └── sleep(1)
```

### After (Event-Driven)
```
Event Scheduler:
├── Trading Loop (60s)
│   └── execute_trading_cycle()
├── Risk Management (1s)
│   └── execute_risk_management()
├── Status Reporting (60s)
│   └── execute_status_reporting()
└── Market Data (5s)
    └── update_market_data()
```

## Key Benefits

### 1. Data Consistency
- **Atomic transactions** ensure all-or-nothing updates
- **State validation** prevents invalid states
- **Consistent snapshots** for read operations
- **No race conditions** between concurrent operations

### 2. Resource Efficiency
- **No busy loops** - CPU only used when needed
- **Event-driven** - tasks run when scheduled
- **Concurrent execution** - multiple tasks run simultaneously
- **Proper cleanup** - resources released when done

### 3. Reliability
- **Thread-safe operations** prevent data corruption
- **Error isolation** - one task failure doesn't affect others
- **Graceful shutdown** - proper cleanup on exit
- **State recovery** - consistent state after failures

### 4. Scalability
- **Concurrent processing** - handle multiple operations simultaneously
- **Configurable intervals** - adjust based on requirements
- **Resource management** - efficient use of system resources
- **Extensible design** - easy to add new scheduled tasks

## Configuration

### Event-Driven App Configuration
```yaml
global:
  # Trading decision interval (seconds)
  decision_interval_sec: 60

  # Risk management interval (seconds)
  risk_loop_interval_sec: 1

  # Status reporting interval (seconds)
  log_status_every: 60

  # Maximum concurrent positions
  max_positions: 5
```

### Redis Configuration
```yaml
# Optional Redis configuration for state persistence
redis:
  url: "redis://localhost:6379"
  namespace: "dhan_scalper:state"
```

## Usage Examples

### 1. Using Atomic State Manager
```ruby
# Initialize state manager
state_manager = DhanScalper::Support::AtomicStateManager.new

# Atomic balance update
state_manager.atomic_balance_update("debit") do |state|
  state[:available] = Money.subtract(state[:available], amount)
  state[:used] = Money.add(state[:used], amount)
  state[:total] = Money.add(state[:available], state[:used])
  state
end

# Get consistent snapshot
snapshot = state_manager.balance_snapshot
```

### 2. Using Event-Driven Scheduler
```ruby
# Initialize scheduler
scheduler = DhanScalper::Support::EventDrivenScheduler.new
scheduler.start

# Schedule recurring task
scheduler.schedule_recurring("trading", 60) do
  execute_trading_logic
end

# Schedule one-time task
scheduler.schedule_once("cleanup", 300) do
  cleanup_resources
end

# Stop scheduler
scheduler.stop
```

### 3. Using Event-Driven App
```ruby
# Initialize app
app = DhanScalper::EventDrivenApp.new(config, quiet: false, enhanced: true)

# Start app (starts all scheduled tasks)
app.start

# App runs event-driven
# ... trading happens automatically ...

# Stop app (stops all tasks gracefully)
app.stop
```

## CLI Usage

### Event-Driven Mode
```bash
# Start event-driven trading
bundle exec exe/dhan_scalper event-driven -c config/scalper.yml

# With timeout
bundle exec exe/dhan_scalper event-driven -c config/scalper.yml -t 30

# Quiet mode
bundle exec exe/dhan_scalper event-driven -c config/scalper.yml -q
```

### Traditional Mode (Still Available)
```bash
# Original paper trading mode
bundle exec exe/dhan_scalper paper -c config/scalper.yml
```

## Migration Guide

### From Busy Loops to Event-Driven

**Old Code:**
```ruby
def main_loop
  while running
    check_risk
    update_positions
    sleep(1)
  end
end
```

**New Code:**
```ruby
def start
  scheduler.schedule_recurring("risk_check", 1) { check_risk }
  scheduler.schedule_recurring("position_update", 1) { update_positions }
end
```

### From Direct State Updates to Atomic Updates

**Old Code:**
```ruby
def update_balance(amount)
  @available -= amount
  @used += amount
  @total = @available + @used
end
```

**New Code:**
```ruby
def update_balance(amount)
  @state_manager.atomic_balance_update("update") do |state|
    state[:available] = Money.subtract(state[:available], amount)
    state[:used] = Money.add(state[:used], amount)
    state[:total] = Money.add(state[:available], state[:used])
    state
  end
end
```

## Performance Impact

### Before
- **CPU Usage**: High (busy loops)
- **Memory**: Inconsistent state
- **Concurrency**: Race conditions
- **Reliability**: Data corruption possible

### After
- **CPU Usage**: Low (event-driven)
- **Memory**: Consistent state
- **Concurrency**: Thread-safe
- **Reliability**: Data integrity guaranteed

## Monitoring and Debugging

### Logging
All operations are logged with component identification:
```
[2025-09-12 21:20:30] INFO  -- : AtomicStateManager: Atomic balance update: debit
[2025-09-12 21:20:30] INFO  -- : EventScheduler: Scheduling recurring task 'trading_loop'
[2025-09-12 21:20:30] INFO  -- : EventDrivenApp: Trading cycle executed
```

### State Inspection
```ruby
# Get current state snapshot
snapshot = wallet.state_snapshot
puts "Available: ₹#{Money.dec(snapshot[:available])}"
puts "Used: ₹#{Money.dec(snapshot[:used])}"
puts "Total: ₹#{Money.dec(snapshot[:total])}"
```

### Task Monitoring
```ruby
# Check active tasks
scheduler.active_tasks
# => ["trading_loop", "risk_management", "status_reporting"]
```

## Best Practices

### 1. State Management
- Always use atomic operations for state updates
- Validate state before and after operations
- Use consistent snapshots for read operations
- Handle errors gracefully

### 2. Task Scheduling
- Use appropriate intervals for different tasks
- Avoid blocking operations in scheduled tasks
- Handle errors in task execution
- Clean up resources properly

### 3. Concurrency
- Use atomic operations for shared state
- Avoid shared mutable state
- Use proper synchronization primitives
- Test concurrent scenarios

### 4. Error Handling
- Isolate errors between tasks
- Log errors with context
- Implement retry logic where appropriate
- Graceful degradation on failures

## Conclusion

The concurrency and state management improvements provide:

- **Data Integrity**: Atomic operations prevent corruption
- **Resource Efficiency**: Event-driven architecture eliminates waste
- **Reliability**: Thread-safe operations ensure consistency
- **Scalability**: Concurrent processing handles multiple operations
- **Maintainability**: Clear separation of concerns and proper error handling

These improvements make DhanScalper production-ready for high-frequency trading scenarios where data consistency and resource efficiency are critical! 🚀
