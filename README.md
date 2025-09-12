# DhanScalper

A production-ready automated options scalping bot built on DhanHQ v2 API with allocation-based position sizing, real-time TTY dashboard, and comprehensive risk management.

## Features

- **Automated Options Scalping**: EMA(20/50) + RSI(14) strategy on 1m and 5m timeframes
- **Allocation-Based Sizing**: Dynamic position sizing based on available balance and risk parameters
- **Real-Time Dashboard**: TTY-based live monitoring with balance, positions, and P&L
- **Paper & Live Trading**: Switch between paper trading and live execution with validation
- **Risk Management**: Session targets, max day loss, trailing stops, and signal invalidation
- **WebSocket Integration**: Real-time market data via DhanHQ WebSocket API
- **Multi-Symbol Support**: Configurable for NIFTY, BANKNIFTY, SENSEX
- **Comprehensive PnL Tracking**: Real-time realized and unrealized P&L calculations
- **Order Validation**: Prevents over-sized orders with balance and position checks
- **CLI Tools**: View positions, balance, orders, and trading metrics

## Installation

### Prerequisites

- Ruby 3.2+
- DhanHQ API v2 enabled account
- Valid API credentials

### Setup

1. **Clone and install dependencies:**
```bash
git clone https://github.com/shubhamtaywade82/dhan_scalper.git
cd dhan_scalper
bundle install
```

2. **Configure credentials:**
```bash
# Copy and edit the environment file
cp .env.example .env

# Set your DhanHQ API credentials
export CLIENT_ID=your_client_id_here
export ACCESS_TOKEN=your_access_token_here
```

3. **Configure trading parameters:**
```bash
# Edit config/scalper.yml with your preferences
vim config/scalper.yml
```

## Configuration

### Environment Variables

**Required:**
- `CLIENT_ID`: Your DhanHQ API client ID
- `ACCESS_TOKEN`: Your DhanHQ API access token

**Optional:**
- `LOG_LEVEL`: DEBUG|INFO (default: INFO)
- `NIFTY_IDX_SID`: NIFTY index security ID (default: 13)
- `BANKNIFTY_IDX_SID`: BANKNIFTY index security ID (default: 532)
- `SENSEX_IDX_SID`: SENSEX index security ID (default: 1)
- `SCALPER_CONFIG`: Path to config file (default: config/scalper.yml)

### Configuration File (config/scalper.yml)

```yaml
symbols: ["NIFTY"]  # Add: BANKNIFTY, SENSEX

global:
  min_profit_target: 1000        # Session target (₹)
  max_day_loss: 1500             # Cutoff (₹)
  charge_per_order: 20           # Flat per order (₹)
  allocation_pct: 0.30           # 30% of balance per position
  slippage_buffer_pct: 0.01      # Sizing cushion
  max_lots_per_trade: 10         # Max lots per trade
  decision_interval: 10          # Signal check interval (seconds)
  tp_pct: 0.35                   # Take profit percentage
  sl_pct: 0.18                   # Stop loss percentage
  trail_pct: 0.12                # Trailing stop percentage
  log_level: "INFO"

paper:
  starting_balance: 200000       # Paper trading balance

SYMBOLS:
  NIFTY:
    idx_sid: "13"                # Index security ID
    seg_idx: "IDX_I"            # Index segment
    seg_opt: "NSE_FNO"          # Options segment
    strike_step: 50              # Strike price interval
    lot_size: 75                 # Contract lot size
    qty_multiplier: 1            # Quantity multiplier
    expiry_wday: 4               # Expiry weekday (Thu)
```

## Usage

### Paper Trading (Recommended for testing)

```bash
# Start paper trading
bundle exec exe/dhan_scalper paper -c config/scalper.yml

# Or use the paper alias
bundle exec exe/dhan_scalper paper
```

### Live Trading

```bash
# Start live trading (use with caution!)
bundle exec exe/dhan_scalper start -c config/scalper.yml

# Or specify mode explicitly
bundle exec exe/dhan_scalper start -m live -c config/scalper.yml
```

### CLI Tools & State Management

#### View Trading State

```bash
# View current balance (paper/live)
bundle exec exe/dhan_scalper balance
bundle exec exe/dhan_scalper balance -m live

# View open positions
bundle exec exe/dhan_scalper positions
bundle exec exe/dhan_scalper positions -m live

# View order history
bundle exec exe/dhan_scalper orders
bundle exec exe/dhan_scalper orders -l 20  # Show last 20 orders

# View live market data
bundle exec exe/dhan_scalper live
bundle exec exe/dhan_scalper live --instruments "NIFTY:IDX_I:13,BANKNIFTY:IDX_I:25"
```

#### System Status & Health

```bash
# Check DhanHQ configuration
bundle exec exe/dhan_scalper config

# View runtime health (Redis, subscriptions, positions)
bundle exec exe/dhan_scalper status

# Generate session reports
bundle exec exe/dhan_scalper report --latest
bundle exec exe/dhan_scalper report --session-id SESSION_ID

# Export historical data
bundle exec exe/dhan_scalper export --since 2024-01-01
```

#### Data Management

```bash
# Reset paper trading balance
bundle exec exe/dhan_scalper reset-balance -a 200000

# Clear all virtual data (orders, positions, balance)
bundle exec exe/dhan_scalper clear-data

# Show real-time dashboard
bundle exec exe/dhan_scalper dashboard
```

### Metrics & Monitoring

#### Real-Time Metrics

The system provides comprehensive metrics through multiple interfaces:

**CLI Status Command:**
```bash
bundle exec exe/dhan_scalper status
```
Shows:
- Redis connection status
- Active WebSocket subscriptions
- Open positions count
- Session PnL
- Heartbeat status

**Balance Command:**
```bash
bundle exec exe/dhan_scalper balance
```
Shows:
- Available balance
- Used balance (in positions)
- Total balance
- Realized PnL (for paper mode)

**Positions Command:**
```bash
bundle exec exe/dhan_scalper positions
```
Shows:
- Symbol and quantity
- Entry price vs current price
- Real-time PnL per position
- Position side (LONG/SHORT)

#### Session Reporting

**Generate Reports:**
```bash
# Latest session
bundle exec exe/dhan_scalper report --latest

# Specific session
bundle exec exe/dhan_scalper report --session-id 2024-01-15_09-30-00
```

**Report Contents:**
- Session start/end times
- Starting vs final balance
- Total realized PnL
- Win rate and trade statistics
- Position breakdown
- Fee analysis

#### Data Export

**Export Historical Data:**
```bash
# Export since specific date
bundle exec exe/dhan_scalper export --since 2024-01-01
```

**Export Format (CSV):**
- Timestamp, Segment, Security ID
- LTP, Day High, Day Low, ATP, Volume
- Sorted by timestamp for analysis

## Trading Strategy

### Signal Generation

The bot uses a multi-timeframe trend-following strategy:

1. **1-minute timeframe**: EMA(20) vs EMA(50) + RSI(14)
2. **5-minute timeframe**: EMA(20) vs EMA(50) + RSI(14)

**Entry Conditions:**
- **Long CE**: Both timeframes bullish (EMA fast > EMA slow, RSI > threshold)
- **Long PE**: Both timeframes bearish (EMA fast < EMA slow, RSI < threshold)

### Position Sizing

- **Allocation-based**: Uses `allocation_pct` of available balance
- **Risk-adjusted**: Applies slippage buffer for conservative sizing
- **Lot-based**: Calculates optimal lot size based on premium and balance
- **Constraints**: Respects `max_lots_per_trade` and `qty_multiplier`

### Risk Management

- **Take Profit**: Closes at `tp_pct` above entry
- **Stop Loss**: Closes at `sl_pct` below entry
- **Trailing Stop**: Activates after `trail_pct` profit, trails at half rate
- **Signal Invalidation**: Closes if opposite signal appears
- **Session Limits**: Stops at target profit or max day loss

### Order Validation

The system includes comprehensive validation to prevent invalid trades:

**Buy Order Validation:**
- Checks if `balance >= (ltp × quantity + fees)`
- Returns `INSUFFICIENT_BALANCE` error if validation fails
- No side effects if validation fails

**Sell Order Validation:**
- Checks if `net_quantity >= sell_quantity`
- Returns `INSUFFICIENT_POSITION` error if validation fails
- No side effects if validation fails

**Price Validation:**
- Ensures valid LTP is available before order execution
- Returns `INVALID_PRICE` error if price unavailable
- Prevents orders with zero or negative prices

**Error Handling:**
- Descriptive error messages with specific amounts
- State preservation (no balance/position changes on failure)
- Structured error responses for programmatic handling

## PnL Calculations & Cash Flow

### Realized PnL (Closed Positions)

Realized PnL is calculated when positions are closed and represents actual profit/loss:

```ruby
# For a complete position exit:
realized_pnl = (exit_price - entry_price) * quantity - total_fees

# For partial exits (weighted average):
realized_pnl = (exit_price - weighted_avg_entry) * exit_quantity - exit_fees
```

**Example:**
- Buy 100 NIFTY CE @ ₹50 (entry fee: ₹20)
- Sell 100 NIFTY CE @ ₹60 (exit fee: ₹20)
- Realized PnL = (60 - 50) × 100 - (20 + 20) = ₹960

### Unrealized PnL (Open Positions)

Unrealized PnL shows current market value of open positions:

```ruby
unrealized_pnl = (current_ltp - weighted_avg_entry) * net_quantity
```

**Example:**
- Buy 100 NIFTY CE @ ₹50
- Current LTP: ₹55
- Unrealized PnL = (55 - 50) × 100 = ₹500

### Cash Flow Management

**Paper Mode:**
- Starting balance: ₹200,000 (configurable)
- Available balance = Total - Used in positions
- Used balance = Sum of (entry_price × quantity) for all positions
- Total balance = Starting + Realized PnL + Unrealized PnL

**Live Mode:**
- Uses actual DhanHQ account balance
- Real-time balance updates via API
- Position values calculated using current LTP

### Fee Structure

- **Per Order Fee**: ₹20 (configurable via `charge_per_order`)
- **Applied to**: Both entry and exit orders
- **Deducted from**: Available balance immediately
- **Tracked separately**: For accurate PnL calculations

## Trading Modes

### Paper Trading Mode

**Purpose**: Test strategies without real money risk

**Features:**
- Virtual balance starting at ₹200,000
- Simulated order execution with realistic delays
- Full position tracking and PnL calculations
- Order validation (balance and position checks)
- Complete trading history and reporting

**Usage:**
```bash
# Start paper trading
bundle exec exe/dhan_scalper paper

# With custom config
bundle exec exe/dhan_scalper paper -c config/scalper.yml

# Quiet mode (no dashboard)
bundle exec exe/dhan_scalper paper --quiet
```

### Live Trading Mode

**Purpose**: Execute real trades with actual money

**Features:**
- Real DhanHQ account integration
- Live market data and order execution
- Real-time balance and position updates
- Same risk management and validation as paper mode

**Usage:**
```bash
# Start live trading (use with caution!)
bundle exec exe/dhan_scalper start -m live

# With custom config
bundle exec exe/dhan_scalper start -m live -c config/scalper.yml
```

### Key Differences

| Feature        | Paper Mode         | Live Mode             |
| -------------- | ------------------ | --------------------- |
| **Balance**    | Virtual (₹200,000) | Real account balance  |
| **Orders**     | Simulated          | Real DhanHQ API calls |
| **Risk**       | None               | Real money at risk    |
| **Data**       | WebSocket + Cache  | WebSocket + API       |
| **Validation** | Full validation    | Full validation       |
| **Reporting**  | CSV + Console      | CSV + Console + API   |

## Dashboard Controls

- **q**: Quit the application
- **p**: Pause trading
- **r**: Resume trading
- **s**: Toggle subscriptions view

## Development

### Running Tests

```bash
bundle exec rake spec
bundle exec rake rubocop
```

### Interactive Console

```bash
bundle exec bin/console
```

### Building the Gem

```bash
bundle exec rake build
bundle exec rake install
```

## Architecture

### Core Components

- **App**: Main application orchestrator
- **Trader**: Individual symbol trading logic
- **Trend**: Signal generation engine
- **QuantitySizer**: Position sizing calculator
- **BalanceProviders**: Account balance management
- **Brokers**: Order execution (Paper/Live)
- **OptionPicker**: Unified option discovery and expiry management
- **CsvMaster**: DhanHQ master data integration for security ID lookup
- **UI::Dashboard**: Real-time TTY interface

### Data Flow

1. WebSocket receives market data
2. TickCache stores latest prices
3. Trend engine analyzes for signals
4. OptionPicker finds ATM strikes using CSV master data
5. QuantitySizer calculates position size
6. Broker executes orders
7. Dashboard displays live state

### CSV Master Data Integration

DhanScalper integrates with the [DhanHQ API scrip master detailed CSV](https://images.dhan.co/api-data/api-scrip-master-detailed.csv) to:

- **Fetch Real Expiry Dates**: Gets actual option expiry dates from the master data
- **Lookup Security IDs**: Finds correct security IDs for specific options (symbol, expiry, strike, type)
- **Get Lot Sizes**: Retrieves contract sizes for position calculations
- **Caching**: Automatically caches the CSV data locally for 24 hours to improve performance

The system supports both `OPTIDX` (index options like NIFTY) and `OPTFUT` (futures options) instrument types.

## Safety Features

- **Paper Trading Mode**: Test strategies without real money
- **Balance Checks**: Prevents over-leveraging
- **Graceful Shutdown**: Handles SIGINT/SIGTERM properly
- **Error Handling**: Continues operation on non-critical errors
- **Logging**: Comprehensive logging for debugging

## Compliance & Best Practices

- Respect broker terms of service
- Handle API rate limits gracefully
- Implement proper error handling
- Use paper trading for strategy validation
- Monitor system resources and performance

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE.txt](LICENSE.txt) file for details.

## Disclaimer

This software is for educational and research purposes. Trading involves substantial risk of loss and is not suitable for all investors. Past performance does not guarantee future results. Use at your own risk.

## Support

For issues and questions:
- Create an issue on GitHub
- Check the configuration examples
- Review the logs for error details
- Ensure your DhanHQ API credentials are valid
