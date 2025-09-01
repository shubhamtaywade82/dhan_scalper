# DhanScalper

A production-ready automated options scalping bot built on DhanHQ v2 API with allocation-based position sizing, real-time TTY dashboard, and comprehensive risk management.

## Features

- **Automated Options Scalping**: EMA(20/50) + RSI(14) strategy on 1m and 3m timeframes
- **Allocation-Based Sizing**: Dynamic position sizing based on available balance and risk parameters
- **Real-Time Dashboard**: TTY-based live monitoring with balance, positions, and P&L
- **Paper & Live Trading**: Switch between paper trading and live execution
- **Risk Management**: Session targets, max day loss, trailing stops, and signal invalidation
- **WebSocket Integration**: Real-time market data via DhanHQ WebSocket API
- **Multi-Symbol Support**: Configurable for NIFTY, BANKNIFTY, SENSEX

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

### Other Commands

```bash
# View virtual orders
bundle exec exe/dhan_scalper orders

# View virtual positions
bundle exec exe/dhan_scalper positions

# View account balance
bundle exec exe/dhan_scalper balance

# Reset virtual balance
bundle exec exe/dhan_scalper reset-balance -a 100000

# Clear all virtual data
bundle exec exe/dhan_scalper clear-data

# Show real-time dashboard
bundle exec exe/dhan_scalper dashboard
```

## Trading Strategy

### Signal Generation

The bot uses a multi-timeframe trend-following strategy:

1. **1-minute timeframe**: EMA(20) vs EMA(50) + RSI(14)
2. **3-minute timeframe**: EMA(20) vs EMA(50) + RSI(14)

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
