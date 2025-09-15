# DhanScalper Redis Keys & Data Structures

## Namespace
- **Default**: `dhan_scalper:v1`
- **Configurable**: Via `global.redis_namespace` in config
- **State Namespace**: `dhan_scalper:state` (for AtomicStateManager)

## Redis Key Categories

### 1. Configuration & Metadata
| Key Pattern                     | Data Type     | TTL | Purpose                  | Example                          |
| ------------------------------- | ------------- | --- | ------------------------ | -------------------------------- |
| `{namespace}:cfg`               | String (JSON) | 24h | System configuration     | `dhan_scalper:v1:cfg`            |
| `{namespace}:csv:raw`           | Hash          | 24h | CSV master data checksum | `dhan_scalper:v1:csv:raw`        |
| `{namespace}:universe:sids`     | Set           | 24h | Universe security IDs    | `dhan_scalper:v1:universe:sids`  |
| `{namespace}:sym:{symbol}:meta` | Hash          | 24h | Symbol metadata          | `dhan_scalper:v1:sym:NIFTY:meta` |

### 2. Market Data & Ticks
| Key Pattern                                         | Data Type | TTL | Purpose                | Example                                  |
| --------------------------------------------------- | --------- | --- | ---------------------- | ---------------------------------------- |
| `{namespace}:ticks:{segment}:{security_id}`         | Hash      | 5m  | Real-time tick data    | `dhan_scalper:v1:ticks:IDX_I:13`         |
| `{namespace}:bars:{segment}:{security_id}:{minute}` | List      | 24h | Minute bars (last 100) | `dhan_scalper:v1:bars:IDX_I:13:20250113` |

### 3. Orders & Trading
| Key Pattern                              | Data Type | TTL | Purpose              | Example                                 |
| ---------------------------------------- | --------- | --- | -------------------- | --------------------------------------- |
| `{namespace}:order:{order_id}`           | Hash      | 24h | Order details        | `dhan_scalper:v1:order:P-1234567890`    |
| `{namespace}:orders:{mode}:{session_id}` | List      | 24h | Session order IDs    | `dhan_scalper:v1:orders:paper:20250113` |
| `{namespace}:idemp:{idempotency_key}`    | String    | 24h | Idempotency tracking | `dhan_scalper:v1:idemp:buy_NIFTY_12345` |

### 4. Positions & PnL
| Key Pattern                                           | Data Type | TTL | Purpose              | Example                                       |
| ----------------------------------------------------- | --------- | --- | -------------------- | --------------------------------------------- |
| `{namespace}:pos:{position_id}`                       | Hash      | 24h | Position details     | `dhan_scalper:v1:pos:pos_12345`               |
| `{namespace}:pos:open`                                | Set       | 24h | Open position IDs    | `dhan_scalper:v1:pos:open`                    |
| `{namespace}:pnl:session`                             | Hash      | 24h | Session PnL data     | `dhan_scalper:v1:pnl:session`                 |
| `{namespace}:position:{segment}:{security_id}:{side}` | Hash      | -   | Atomic position data | `dhan_scalper:v1:position:NSE_FNO:12345:LONG` |

### 5. State Management (AtomicStateManager)
| Key Pattern                   | Data Type | TTL | Purpose         | Example                        |
| ----------------------------- | --------- | --- | --------------- | ------------------------------ |
| `{state_namespace}:balance`   | Hash      | -   | Balance state   | `dhan_scalper:state:balance`   |
| `{state_namespace}:positions` | Hash      | -   | Positions state | `dhan_scalper:state:positions` |

### 6. Reports & Analytics
| Key Pattern                        | Data Type | TTL | Purpose         | Example                            |
| ---------------------------------- | --------- | --- | --------------- | ---------------------------------- |
| `{namespace}:reports:{session_id}` | Hash      | 24h | Session reports | `dhan_scalper:v1:reports:20250113` |

### 7. System & Monitoring
| Key Pattern                            | Data Type | TTL      | Purpose                        | Example                                 |
| -------------------------------------- | --------- | -------- | ------------------------------ | --------------------------------------- |
| `{namespace}:hb`                       | Hash      | 5m       | Heartbeat (process monitoring) | `dhan_scalper:v1:hb`                    |
| `{namespace}:locks:{lock_name}`        | String    | Variable | Distributed locks              | `dhan_scalper:v1:locks:position_update` |
| `{namespace}:throttle:{throttle_name}` | String    | Variable | Rate limiting                  | `dhan_scalper:v1:throttle:api_calls`    |

### 8. Instrument Cache
| Key Pattern                        | Data Type     | TTL      | Purpose               | Example                             |
| ---------------------------------- | ------------- | -------- | --------------------- | ----------------------------------- |
| `{namespace}:instruments:{symbol}` | String (JSON) | Variable | Instrument data cache | `dhan_scalper:v1:instruments:nifty` |
| `{namespace}:instruments:cache`    | Hash          | Variable | Cache metadata        | `dhan_scalper:v1:instruments:cache` |

## Data Structure Details

### Tick Data Hash Structure
```ruby
# Key: dhan_scalper:v1:ticks:IDX_I:13
{
  "ltp" => "81904.703125",      # Last traded price
  "ts" => "1757696401",         # Timestamp
  "atp" => "0.0",               # Average traded price
  "vol" => "0",                 # Volume
  "segment" => "IDX_I",         # Exchange segment
  "security_id" => "13"         # Security ID
}
```

### Order Data Hash Structure
```ruby
# Key: dhan_scalper:v1:order:P-1234567890
{
  "id" => "P-1234567890",
  "security_id" => "12345",
  "side" => "LONG",
  "quantity" => "75",
  "price" => "100.0",
  "timestamp" => "1757696401",
  "status" => "filled"
}
```

### Position Data Hash Structure
```ruby
# Key: dhan_scalper:v1:pos:pos_12345
{
  "id" => "pos_12345",
  "security_id" => "12345",
  "side" => "LONG",
  "quantity" => "75",
  "entry_price" => "100.0",
  "current_price" => "105.0",
  "unrealized_pnl" => "375.0",
  "realized_pnl" => "0.0"
}
```

### Session PnL Hash Structure
```ruby
# Key: dhan_scalper:v1:pnl:session
{
  "realized" => "1500.0",       # Realized PnL
  "unrealized" => "750.0",      # Unrealized PnL
  "fees" => "120.0",            # Total fees
  "total" => "2130.0",          # Total PnL
  "timestamp" => "1757696401"   # Last update timestamp
}
```

### Balance State Hash Structure (AtomicStateManager)
```ruby
# Key: dhan_scalper:state:balance
{
  "available" => "192480.0",    # Available balance
  "used" => "7520.0",           # Used balance
  "total" => "200000.0",        # Total balance
  "realized_pnl" => "0.0"       # Realized PnL
}
```

## Usage Patterns

### Hot Cache Layer
- **In-memory cache** for frequently accessed data (1-second TTL)
- **Cache keys**: `{segment}:{security_id}` and `{segment}:{security_id}:ltp`
- **Purpose**: Reduce Redis calls for high-frequency operations

### Atomic Operations
- **Multi/Exec transactions** for balance and position updates
- **Lua scripts** for complex atomic operations
- **Distributed locks** for critical sections

### TTL Strategy
- **Short TTL (5m)**: Tick data, heartbeats
- **Medium TTL (24h)**: Orders, positions, reports
- **No TTL**: State data, locks (manual cleanup)

### Key Naming Convention
- **Hierarchical**: `{namespace}:{category}:{identifier}`
- **Consistent**: All keys follow the same pattern
- **Scalable**: Easy to add new categories
- **Queryable**: Supports pattern matching with `KEYS` command

## Redis Operations Used

### Data Types
- **Strings**: Configuration, locks, throttles
- **Hashes**: Tick data, orders, positions, PnL
- **Lists**: Order history, minute bars
- **Sets**: Open positions, universe SIDs

### Commands
- **Basic**: GET, SET, DEL, EXISTS
- **Hash**: HSET, HGET, HGETALL, HMSET
- **List**: LPUSH, LRANGE, LTRIM
- **Set**: SADD, SREM, SMEMBERS, SISMEMBER
- **Advanced**: EXPIRE, MULTI/EXEC, EVAL (Lua scripts)
