# 📊 DhanScalper Paper Mode - Complete Guide

## Overview

DhanScalper Paper Mode is a comprehensive paper trading system that allows you to test your options trading strategies without risking real money. It provides real-time market data, automated signal analysis, and detailed session reporting.

## 🚀 Quick Start

### 1. Basic Paper Trading
```bash
# Start paper trading with default settings
bundle exec exe/dhan_scalper paper

# Start with custom configuration
bundle exec exe/dhan_scalper paper -c config/scalper.yml

# Start in quiet mode (better for terminals)
bundle exec exe/dhan_scalper paper -q

# Start with timeout (auto-exit after 30 minutes)
bundle exec exe/dhan_scalper paper -t 30
```

### 2. Demo Mode
```bash
# Run the interactive demo
bundle exec ruby examples/paper_mode_demo.rb
```

## 🎯 Key Features

### ✅ **Real-time Market Data**
- WebSocket connection to DhanHQ for live price feeds
- Automatic subscription to underlying indices and options
- Real-time P&L calculation and position tracking

### ✅ **Automated Signal Analysis**
- Holy Grail indicator integration for trend analysis
- Multi-timeframe analysis (1m + 5m/15m)
- Automated buy signals for CE/PE options

### ✅ **Smart Option Selection**
- ATM (At-The-Money) option selection
- ATM±1 strike monitoring for better entries
- Integration with CSV master data for accurate security IDs

### ✅ **Risk Management**
- Daily loss limits and position limits
- Real-time P&L monitoring
- Automatic position sizing based on available balance

### ✅ **Comprehensive Reporting**
- Session reports in JSON and CSV formats
- Detailed trade history and performance metrics
- Risk analysis and win rate calculations

## 📋 Configuration

### Basic Configuration (`config/scalper.yml`)
```yaml
symbols: ["NIFTY"] # Symbols to trade

global:
  min_profit_target: 1000    # Session target (₹)
  max_day_loss: 5000         # Daily loss limit (₹)
  decision_interval: 10       # Signal check interval (seconds)
  use_multi_timeframe: true  # Enable multi-timeframe analysis
  secondary_timeframe: 5     # Secondary timeframe (minutes)

paper:
  starting_balance: 200000   # Starting virtual balance (₹)

SYMBOLS:
  NIFTY:
    idx_sid: "13"            # NIFTY index security ID
    seg_idx: "IDX_I"         # Index segment
    seg_opt: "NSE_FNO"       # Options segment
    strike_step: 50          # Strike price step
    lot_size: 75             # Contract size
```

## 🔧 Advanced Usage

### 1. Custom Exchange Segments
The system automatically maps exchange segments using the CSV master data:
```ruby
# NSE Index → IDX_I
# NSE Equity → NSE_EQ
# NSE Derivatives → NSE_FNO
# BSE Equity → BSE_EQ
# MCX Commodity → MCX_COMM
```

### 2. Session Reporting
```bash
# View latest session report
bundle exec exe/dhan_scalper report --latest

# View specific session
bundle exec exe/dhan_scalper report --session-id PAPER_20241208_143022

# List all available sessions
bundle exec exe/dhan_scalper report
```

### 3. Position Monitoring
```bash
# View current positions
bundle exec exe/dhan_scalper positions

# View virtual balance
bundle exec exe/dhan_scalper balance

# View order history
bundle exec exe/dhan_scalper orders
```

## 📊 Session Reports

### Report Structure
Each session generates two files:
- **JSON Report**: `data/reports/session_PAPER_YYYYMMDD_HHMMSS.json`
- **CSV Report**: `data/reports/session_PAPER_YYYYMMDD_HHMMSS.csv`

### Report Contents
- **Session Summary**: Duration, symbols traded, mode
- **Trading Performance**: Total trades, win rate, success/failure counts
- **Financial Summary**: Starting/ending balance, P&L, max profit/drawdown
- **Position Details**: All positions with entry prices and current P&L
- **Trade History**: Complete trade log with timestamps
- **Risk Metrics**: Risk-reward ratios and drawdown analysis

### Sample Report Output
```
================================================================================
📊 SESSION REPORT - PAPER_20241208_143022
================================================================================

🕐 SESSION INFO:
  Mode: PAPER
  Duration: 5.2 minutes
  Start: 2024-12-08 14:30:22
  End: 2024-12-08 14:35:34
  Symbols: NIFTY

📈 TRADING PERFORMANCE:
  Total Trades: 3
  Successful: 2
  Failed: 1
  Win Rate: 66.67%

💰 FINANCIAL SUMMARY:
  Starting Balance: ₹200000.00
  Ending Balance: ₹198750.00
  Total P&L: ₹-1250.00
  Max Profit: ₹500.00
  Max Drawdown: ₹-1250.00
  Avg Trade P&L: ₹-416.67

✅ SESSION RESULT: LOSS
================================================================================
```

## 🛠️ Troubleshooting

### Common Issues

1. **WebSocket Connection Failed**
   - Check your DhanHQ API credentials in `.env`
   - Ensure internet connectivity
   - Verify API key permissions

2. **No Price Data Available**
   - Market might be closed
   - Check if symbols are correctly configured
   - Verify security IDs in CSV master data

3. **Option Selection Failed**
   - Check if expiry dates are available
   - Verify strike steps and lot sizes
   - Ensure CSV master data is up to date

4. **Session Report Not Generated**
   - Check if `data/reports/` directory exists
   - Verify file permissions
   - Look for error messages in console output

### Debug Mode
```bash
# Enable debug logging
bundle exec exe/dhan_scalper paper -c config/scalper.yml

# Check configuration
bundle exec exe/dhan_scalper config
```

## 📈 Performance Tips

### 1. Optimize Decision Interval
- Shorter intervals (5-10s) for scalping strategies
- Longer intervals (30-60s) for swing strategies
- Balance between responsiveness and system load

### 2. Multi-timeframe Analysis
- Enable for better signal quality
- Use 1m + 5m for intraday trading
- Use 1m + 15m for longer-term positions

### 3. Risk Management
- Set appropriate daily loss limits
- Use position sizing based on account balance
- Monitor max drawdown regularly

## 🔄 Integration with Exchange Segment Mapper

The paper mode now uses the new Exchange Segment Mapper for accurate segment identification:

```ruby
# Automatic segment mapping
csv_master.get_exchange_segment("13", exchange: "NSE", segment: "I") # → "IDX_I"
csv_master.get_exchange_segment("13", exchange: "NSE", segment: "C") # → "NSE_CURRENCY"

# Symbol-based lookup
csv_master.get_exchange_segment_by_symbol("NIFTY", "IDX") # → "IDX_I"
```

## 📚 Examples

### Example 1: Basic Paper Trading Session
```bash
# Start a 10-minute paper trading session
bundle exec exe/dhan_scalper paper -t 10 -q

# View the generated report
bundle exec exe/dhan_scalper report --latest
```

### Example 2: Custom Configuration
```yaml
# config/custom_scalper.yml
symbols: ["NIFTY", "BANKNIFTY"]

global:
  decision_interval: 5
  max_day_loss: 10000
  use_multi_timeframe: true
  secondary_timeframe: 15

paper:
  starting_balance: 500000
```

```bash
# Use custom configuration
bundle exec exe/dhan_scalper paper -c config/custom_scalper.yml
```

### Example 3: Demo Script
```bash
# Run the interactive demo
bundle exec ruby examples/paper_mode_demo.rb
```

## 🎉 Getting Started

1. **Setup Environment**
   ```bash
   # Install dependencies
   bundle install

   # Configure DhanHQ credentials
   cp .env.example .env
   # Edit .env with your API credentials
   ```

2. **Run Paper Mode**
   ```bash
   # Start paper trading
   bundle exec exe/dhan_scalper paper
   ```

3. **View Results**
   ```bash
   # Check session reports
   bundle exec exe/dhan_scalper report --latest
   ```

## 📞 Support

For issues and questions:
- Check the troubleshooting section above
- Review the console output for error messages
- Ensure your configuration is correct
- Verify DhanHQ API credentials

---

**Happy Paper Trading! 🚀📊**
