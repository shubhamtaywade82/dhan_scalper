# Live Dashboard Features

This document describes the new live dashboard functionality added to DhanScalper.

## New Features

### 1. Live LTP Dashboard
A real-time dashboard that shows live market data via WebSocket connection to DhanHQ.

**Usage:**
```bash
# Show live LTPs for default instruments (NIFTY, BANKNIFTY, SENSEX)
bundle exec exe/dhan_scalper live

# Show live LTPs for custom instruments
bundle exec exe/dhan_scalper live --instruments "NIFTY:IDX_I:13,BANKNIFTY:IDX_I:25"

# Custom refresh interval
bundle exec exe/dhan_scalper live --interval 1.0

# Use simple dashboard (no full screen control, better for some terminals)
bundle exec exe/dhan_scalper live --simple

# Simple dashboard with custom refresh
bundle exec exe/dhan_scalper live --simple --interval 2.0
```

### 2. Enhanced Trading Dashboard
The trading system now uses the live dashboard by default, showing both:
- Live market LTPs
- Trading positions and P&L
- Account balance
- Recent trades

**Usage:**
```bash
# Start trading with live dashboard
bundle exec exe/dhan_scalper paper

# Start trading in quiet mode (no dashboard)
bundle exec exe/dhan_scalper paper --quiet
```

### 3. Configuration Management
New CLI command to check DhanHQ configuration status.

**Usage:**
```bash
# Check configuration status
bundle exec exe/dhan_scalper config
```

## Configuration

### Environment Variables
Create a `.env` file in the project root:

```env
# DhanHQ API Configuration
CLIENT_ID=your_client_id_here
ACCESS_TOKEN=your_access_token_here

# Optional configuration
BASE_URL=https://api.dhan.co/v2
LOG_LEVEL=INFO

# Trading Configuration
NIFTY_IDX_SID=13
BANKNIFTY_IDX_SID=25
FINNIFTY_IDX_SID=26

# Debug logging for WebSocket ticks (optional)
DHAN_LOG_LEVEL=INFO
```

### Instrument Format
When specifying custom instruments, use the format:
```
name:segment:security_id
```

Examples:
- `NIFTY:IDX_I:13` - NIFTY 50 index
- `BANKNIFTY:IDX_I:25` - BANKNIFTY index
- `FINNIFTY:IDX_I:26` - FINNIFTY index

## Dashboard Types

### Full Screen Dashboard (Default)
- Uses TTY cursor control for smooth updates
- Full screen display with borders and styling
- Optimized for modern terminals
- May cause issues on some terminal emulators

### Simple Dashboard (`--simple` option)
- Basic terminal output without full screen control
- Better compatibility with older terminals
- No scrolling issues
- Recommended for problematic terminals

## Dashboard Features

### Live LTP Section
- Real-time Last Traded Price updates
- Trend indicators (▲ for up, ▼ for down)
- Connection status
- Data freshness indicators

### Trading Data Section (when running trading mode)
- Account balance (Available, Used, Total)
- Open positions with P&L
- Recent closed positions
- Trading status and session P&L

### Status Section
- WebSocket connection status
- Cache statistics
- Last update timestamp
- Exit instructions

## Technical Details

### Services Architecture
- `DhanScalper::Services::DhanHQConfig` - Configuration management
- `DhanScalper::Services::MarketFeed` - WebSocket market data feed
- `DhanScalper::Services::WebSocketCleanup` - Global WebSocket cleanup management
- `DhanScalper::UI::LiveDashboard` - Enhanced dashboard UI

### Tick Cache
Enhanced `TickCache` with additional methods:
- `get(segment, security_id)` - Get full tick data
- `fresh?(segment, security_id)` - Check data freshness
- `stats` - Get cache statistics
- `get_multiple(instruments)` - Get multiple instruments at once

### Thread Safety
All components use thread-safe data structures:
- `Concurrent::Map` for tick cache
- `Concurrent::AtomicReference` for state management
- Proper signal handling for graceful shutdown

### WebSocket Cleanup
Comprehensive cleanup system ensures all WebSocket connections are properly closed:
- Global `at_exit` handlers for automatic cleanup
- Signal handlers for graceful shutdown (INT, TERM)
- Individual service cleanup in `MarketFeed` and `LiveDashboard`
- Multiple fallback methods for disconnecting WebSocket connections

## Troubleshooting

### Common Issues

1. **"Missing required environment variables"**
   - Ensure `.env` file exists with valid `CLIENT_ID` and `ACCESS_TOKEN`
   - Run `bundle exec exe/dhan_scalper config` to check status

2. **"Failed to create WebSocket client"**
   - Check internet connection
   - Verify DhanHQ credentials are valid
   - Check if DhanHQ API is accessible

3. **No live data showing**
   - Ensure market is open
   - Check instrument security IDs are correct
   - Verify WebSocket connection status in dashboard

4. **Dashboard scrolling or flickering issues**
   - Use the simple dashboard: `bundle exec exe/dhan_scalper live --simple`
   - Increase refresh interval: `--interval 2.0`
   - Check terminal compatibility with TTY cursor control

### Debug Mode
Enable debug logging by setting:
```env
DHAN_LOG_LEVEL=DEBUG
```

This will show detailed WebSocket tick information in the console.

## Performance Notes

- Default refresh rate is 0.5 seconds for smooth updates
- WebSocket connection is maintained efficiently
- Tick cache automatically manages memory usage
- Dashboard renders only when data changes

## Future Enhancements

- Support for more instrument types (options, futures)
- Historical data overlay
- Customizable dashboard layouts
- Alert system for price movements
- Export functionality for data analysis
