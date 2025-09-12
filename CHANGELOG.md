## [Unreleased]

## [0.2.0] - 2025-09-12

### Added
- **Comprehensive Order Validation**: Added balance and position validation for all orders
  - Buy orders check `balance >= (ltp × quantity + fees)` before execution
  - Sell orders check `net_quantity >= sell_quantity` before execution
  - Price validation ensures valid LTP is available
  - Returns structured error responses with specific error codes
- **Enhanced PnL Tracking**: Improved realized and unrealized PnL calculations
  - Weighted average entry price for partial position exits
  - Real-time unrealized PnL updates using current LTP
  - Separate tracking of realized PnL in balance provider
  - Comprehensive PnL breakdown in CLI commands
- **PaperBroker API Alignment**: Aligned PaperBroker with DhanHQ API response format
  - Returns Dhan-compatible order responses with `snake_case` keys
  - Includes all required fields: `order_id`, `order_status`, `average_traded_price`, etc.
  - Maintains backward compatibility with existing code
  - Enhanced position objects with derivatives-specific fields
- **CLI Tools Enhancement**: Added comprehensive CLI tools for state management
  - `balance` command shows available, used, and total balance
  - `positions` command displays open positions with real-time PnL
  - `orders` command shows order history with filtering
  - `status` command displays system health and metrics
  - `report` command generates detailed session reports
  - `export` command exports historical data to CSV
- **Documentation Improvements**: Comprehensive documentation updates
  - Detailed PnL calculation examples with numeric scenarios
  - Clear explanation of paper vs live trading modes
  - Complete CLI usage guide with examples
  - Order validation documentation with error codes

### Changed
- **Position Tracking**: Enhanced position objects with additional fields
  - Added `buy_avg`, `buy_qty`, `sell_avg`, `sell_qty`, `net_qty` fields
  - Added `realized_profit`, `unrealized_profit` for PnL tracking
  - Added derivatives-specific fields: `multiplier`, `lot_size`, `strike_price`, etc.
- **Error Handling**: Improved error handling and validation
  - Structured error responses with error codes and messages
  - State preservation during validation failures
  - Descriptive error messages with specific amounts
- **Balance Management**: Enhanced balance tracking and calculations
  - Separate tracking of realized PnL for reporting
  - Real-time equity calculations including unrealized PnL
  - Improved cash flow management in paper mode

### Fixed
- **WebSocket Resilience**: Fixed WebSocket connection issues
  - Resolved `undefined method 'emit_close'` error
  - Added proper connection loss simulation for testing
  - Improved heartbeat and reconnection mechanisms
- **Test Coverage**: Enhanced test suite for new functionality
  - Added comprehensive validation tests (15 new specs)
  - Updated existing tests to work with new API format
  - All tests passing with improved coverage

### Security
- **Order Validation**: Prevents over-sized orders and invalid trades
  - No side effects when validations fail
  - Comprehensive balance and position checks
  - Protection against invalid price data

## [0.1.0] - 2025-09-01

- Initial release
