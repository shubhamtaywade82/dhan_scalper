# Redis Data Contracts - DhanScalper

## Overview
This document defines the minimal required fields and key structures for Redis data persistence in the DhanScalper system. The focus is on **positions**, **orders**, and **sessions** with LTP cache kept in memory for performance.

## Design Principles
- **Minimal fields**: Only essential data for recovery and persistence
- **LTP in memory**: Keep real-time tick data in `Concurrent::Map` for performance
- **Snapshot persistence**: Persist LTP snapshots only when needed for recovery
- **Atomic operations**: Use Redis transactions for consistency
- **TTL strategy**: Appropriate expiration times for different data types

---

## 1. POSITIONS

### Key Pattern
```
{namespace}:pos:{position_id}
```

### Minimal Required Fields
```ruby
{
  # Core identification
  "id" => "pos_12345",                    # Position ID (string)
  "security_id" => "12345",               # Security ID (string)
  "side" => "LONG",                       # LONG/SHORT (string)

  # Position data
  "quantity" => "75",                     # Net quantity (string)
  "entry_price" => "100.0",              # Weighted average entry price (string)
  "entry_fee" => "20.0",                 # Total entry fees (string)

  # Risk management
  "stop_loss" => "95.0",                 # Current stop loss (string, optional)
  "take_profit" => "110.0",              # Current take profit (string, optional)
  "trailing_stop" => "105.0",            # Current trailing stop (string, optional)

  # Timestamps
  "created_at" => "2025-01-13T09:30:00+05:30",  # Position creation (ISO8601)
  "updated_at" => "2025-01-13T10:15:00+05:30",  # Last update (ISO8601)

  # Status
  "status" => "open"                     # open/closed (string)
}
```

### Open Positions Tracking
```
Key: {namespace}:pos:open
Type: Set
TTL: 24h
Purpose: Track all open position IDs for quick recovery
```

### Position Recovery Logic
```ruby
# Load all open positions on restart
open_position_ids = redis.smembers("{namespace}:pos:open")
recovered_positions = open_position_ids.map do |pos_id|
  redis.hgetall("{namespace}:pos:#{pos_id}")
end

# Filter only open positions
active_positions = recovered_positions.select { |pos| pos["status"] == "open" }
```

---

## 2. ORDERS

### Key Pattern
```
{namespace}:order:{order_id}
```

### Minimal Required Fields
```ruby
{
  # Core identification
  "id" => "P-1234567890",                # Order ID (string)
  "security_id" => "12345",              # Security ID (string)
  "side" => "LONG",                      # LONG/SHORT (string)

  # Order details
  "quantity" => "75",                    # Order quantity (string)
  "price" => "100.0",                    # Order price (string)
  "order_type" => "MARKET",              # MARKET/LIMIT (string)

  # Status tracking
  "status" => "filled",                  # pending/filled/cancelled/rejected (string)
  "filled_quantity" => "75",             # Filled quantity (string)
  "filled_price" => "100.0",             # Average filled price (string)

  # Timestamps
  "created_at" => "2025-01-13T09:30:00+05:30",  # Order creation (ISO8601)
  "filled_at" => "2025-01-13T09:30:05+05:30",   # Fill timestamp (ISO8601, optional)

  # Session tracking
  "session_id" => "20250113",            # Session ID (string)
  "mode" => "paper"                      # paper/live (string)
}
```

### Session Order Tracking
```
Key: {namespace}:orders:{mode}:{session_id}
Type: List
TTL: 24h
Purpose: Track all orders for a session
```

### Order Recovery Logic
```ruby
# Load session orders
session_orders = redis.lrange("{namespace}:orders:paper:20250113", 0, -1)
recovered_orders = session_orders.map do |order_id|
  redis.hgetall("{namespace}:order:#{order_id}")
end
```

---

## 3. SESSIONS

### Session PnL Data
```
Key: {namespace}:pnl:session
Type: Hash
TTL: 24h
```

### Minimal Required Fields
```ruby
{
  # PnL tracking
  "realized" => "1500.0",                # Realized PnL (string)
  "unrealized" => "750.0",               # Unrealized PnL (string)
  "fees" => "120.0",                     # Total fees paid (string)
  "total" => "2130.0",                   # Total PnL (string)

  # Session metadata
  "session_id" => "20250113",            # Session ID (string)
  "mode" => "paper",                     # paper/live (string)
  "start_time" => "2025-01-13T09:15:00+05:30",  # Session start (ISO8601)
  "last_update" => "2025-01-13T15:30:00+05:30", # Last update (ISO8601)

  # Trading stats
  "total_trades" => "5",                 # Total trades executed (string)
  "winning_trades" => "3",               # Winning trades (string)
  "losing_trades" => "2",                # Losing trades (string)
  "max_drawdown" => "500.0",             # Maximum drawdown (string)

  # Risk metrics
  "max_positions" => "3",                # Maximum concurrent positions (string)
  "current_positions" => "2"             # Current open positions (string)
}
```

### Session Recovery Logic
```ruby
# Load session state
session_pnl = redis.hgetall("{namespace}:pnl:session")
if session_pnl
  puts "Session PnL: ₹#{session_pnl['total']}"
  puts "Realized: ₹#{session_pnl['realized']}"
  puts "Unrealized: ₹#{session_pnl['unrealized']}"
  puts "Total Trades: #{session_pnl['total_trades']}"
end
```

---

## 4. LTP CACHE STRATEGY

### In-Memory Cache (Primary)
```ruby
# Keep LTP data in memory for performance
class TickCache
  def initialize
    @cache = Concurrent::Map.new
  end

  def put(tick_data)
    key = "#{tick_data[:segment]}:#{tick_data[:security_id]}"
    @cache[key] = {
      ltp: tick_data[:ltp],
      timestamp: tick_data[:ts],
      cached_at: Time.now
    }
  end

  def get(segment, security_id)
    key = "#{segment}:#{security_id}"
    @cache[key]
  end
end
```

### Redis Snapshot (Recovery Only)
```
Key: {namespace}:ltp:snapshot
Type: Hash
TTL: 5m
Purpose: LTP snapshot for recovery after restart
```

### Snapshot Fields
```ruby
{
  "NSE_FNO:12345" => "100.0",           # LTP for security
  "IDX_I:13" => "25000.0",              # LTP for index
  "snapshot_time" => "2025-01-13T15:30:00+05:30"  # Snapshot timestamp
}
```

### Snapshot Logic
```ruby
# Create LTP snapshot for recovery
def create_ltp_snapshot
  snapshot = {}
  @cache.each do |key, data|
    snapshot[key] = data[:ltp].to_s
  end
  snapshot["snapshot_time"] = Time.now.iso8601

  redis.hset("{namespace}:ltp:snapshot", snapshot)
  redis.expire("{namespace}:ltp:snapshot", 300) # 5 minutes TTL
end

# Restore LTP from snapshot
def restore_ltp_snapshot
  snapshot = redis.hgetall("{namespace}:ltp:snapshot")
  return if snapshot.empty?

  snapshot.each do |key, ltp|
    next if key == "snapshot_time"
    segment, security_id = key.split(":")
    @cache["#{segment}:#{security_id}"] = {
      ltp: ltp.to_f,
      timestamp: Time.now.to_i,
      cached_at: Time.now
    }
  end
end
```

---

## 5. ATOMIC OPERATIONS

### Position Updates
```ruby
# Atomic position update
def update_position_atomically(position_id, updates)
  redis.multi do |multi|
    multi.hset("{namespace}:pos:#{position_id}", updates.transform_keys(&:to_s))
    multi.hset("{namespace}:pos:#{position_id}", "updated_at", Time.now.iso8601)
  end
end
```

### Order Creation
```ruby
# Atomic order creation
def create_order_atomically(order_data)
  redis.multi do |multi|
    multi.hset("{namespace}:order:#{order_data[:id]}", order_data.transform_keys(&:to_s))
    multi.lpush("{namespace}:orders:#{order_data[:mode]}:#{order_data[:session_id]}", order_data[:id])
    multi.expire("{namespace}:order:#{order_data[:id]}", 86400)
  end
end
```

### Session PnL Update
```ruby
# Atomic session PnL update
def update_session_pnl_atomically(pnl_data)
  redis.multi do |multi|
    multi.hset("{namespace}:pnl:session", "realized", pnl_data[:realized])
    multi.hset("{namespace}:pnl:session", "unrealized", pnl_data[:unrealized])
    multi.hset("{namespace}:pnl:session", "total", pnl_data[:total])
    multi.hset("{namespace}:pnl:session", "last_update", Time.now.iso8601)
  end
end
```

---

## 6. RECOVERY WORKFLOW

### System Restart Recovery
```ruby
def recover_from_restart
  # 1. Load session state
  session_pnl = redis.hgetall("{namespace}:pnl:session")

  # 2. Load open positions
  open_positions = load_open_positions

  # 3. Restore LTP snapshot (if available)
  restore_ltp_snapshot

  # 4. Resubscribe to position instruments
  resubscribe_to_positions(open_positions)

  # 5. Resume risk management
  resume_risk_management(open_positions)
end

def load_open_positions
  open_position_ids = redis.smembers("{namespace}:pos:open")
  open_position_ids.map do |pos_id|
    position_data = redis.hgetall("{namespace}:pos:#{pos_id}")
    next unless position_data["status"] == "open"
    position_data
  end.compact
end
```

---

## 7. TTL STRATEGY

| Data Type          | TTL | Reason                                     |
| ------------------ | --- | ------------------------------------------ |
| Positions          | 24h | Need for recovery, not frequently accessed |
| Orders             | 24h | Historical data, not frequently accessed   |
| Session PnL        | 24h | Session data, not frequently accessed      |
| LTP Snapshot       | 5m  | Recovery only, short-lived                 |
| Open Positions Set | 24h | Recovery index, not frequently accessed    |

---

## 8. KEY NAMING CONVENTIONS

### Pattern
```
{namespace}:{category}:{identifier}
```

### Examples
```
dhan_scalper:v1:pos:pos_12345
dhan_scalper:v1:order:P-1234567890
dhan_scalper:v1:orders:paper:20250113
dhan_scalper:v1:pnl:session
dhan_scalper:v1:pos:open
dhan_scalper:v1:ltp:snapshot
```

### Benefits
- **Hierarchical**: Easy to understand and navigate
- **Consistent**: All keys follow the same pattern
- **Scalable**: Easy to add new categories
- **Queryable**: Supports pattern matching with `KEYS` command

---

## 9. DATA VALIDATION

### Position Validation
```ruby
def validate_position_data(data)
  required_fields = %w[id security_id side quantity entry_price status]
  required_fields.all? { |field| data.key?(field) }
end
```

### Order Validation
```ruby
def validate_order_data(data)
  required_fields = %w[id security_id side quantity price status session_id mode]
  required_fields.all? { |field| data.key?(field) }
end
```

### Session Validation
```ruby
def validate_session_data(data)
  required_fields = %w[realized unrealized total session_id mode]
  required_fields.all? { |field| data.key?(field) }
end
```

---

## 10. PERFORMANCE CONSIDERATIONS

### Memory Usage
- **LTP cache**: In-memory only, no Redis persistence
- **Position data**: Minimal fields, 24h TTL
- **Order data**: Minimal fields, 24h TTL
- **Session data**: Aggregated data, 24h TTL

### Redis Operations
- **HSET/HGET**: For position and order data
- **SADD/SMEMBERS**: For open positions tracking
- **LPUSH/LRANGE**: For session order tracking
- **MULTI/EXEC**: For atomic operations

### Recovery Performance
- **Fast startup**: Only essential data loaded
- **Lazy loading**: LTP data loaded on demand
- **Incremental recovery**: Positions loaded first, then orders

This data contract ensures minimal Redis usage while maintaining full recovery capabilities and optimal performance for the DhanScalper trading system.
