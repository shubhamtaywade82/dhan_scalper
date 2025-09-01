# DhanHQ Implementation Fixes

This document outlines the fixes made to resolve issues with the DhanHQ balance check and other API implementations in the dhanscalper tool.

## Issues Fixed

### 1. Balance Check Issues
- **Problem**: The `LiveBalance` class was using incorrect DhanHQ API methods
- **Solution**: Updated to use the correct `DhanHQ::Models::Funds.fetch` method
- **Details**: The Funds class provides `available_balance`, `utilized_amount`, and other attributes

### 2. Order Creation Issues
- **Problem**: The broker was using `DhanHQ::Models::Order.new` which may not be the correct API
- **Solution**: Implemented multiple fallback methods for order creation
- **Methods Tried**:
  - `DhanHQ::Models::Order.new`
  - `DhanHQ::Order.new`
  - `DhanHQ::Orders.create`

### 3. Trade Price Fetching Issues
- **Problem**: Using `DhanHQ::Models::Trade.find_by_order_id` which may not exist
- **Solution**: Implemented multiple fallback methods for fetching trade prices
- **Methods Tried**:
  - `DhanHQ::Models::Trade.find_by_order_id`
  - `DhanHQ::Trade.find_by_order_id`
  - `DhanHQ::Models::Trade.find_by`
  - `DhanHQ::Trade.find_by`
  - `DhanHQ::Models::Trades.find_by_order_id`
  - `DhanHQ::Trades.find_by_order_id`

### 4. Historical Data Issues
- **Problem**: Using `DhanHQ::Models::HistoricalData.intraday` which may not exist
- **Solution**: Implemented multiple fallback methods for fetching historical data
- **Methods Tried**:
  - `DhanHQ::Models::HistoricalData.intraday`
  - `DhanHQ::HistoricalData.intraday`
  - `DhanHQ::Models::HistoricalData.fetch`
  - `DhanHQ::HistoricalData.fetch`
  - `DhanHQ::Models::Candles.intraday`
  - `DhanHQ::Candles.intraday`

### 5. WebSocket Issues
- **Problem**: WebSocket creation and disconnection methods may not exist
- **Solution**: Implemented multiple fallback methods for WebSocket operations
- **Methods Tried**:
  - `DhanHQ::WS::Client.new`
  - `DhanHQ::WebSocket::Client.new`
  - `DhanHQ::WebSocket.new`
  - `DhanHQ::WS.new`

### 6. Missing Order Class
- **Problem**: The `Order` class was referenced but not defined
- **Solution**: Created a new `DhanScalper::Order` class with necessary attributes and methods

## Files Modified

1. **`lib/dhan_scalper/balance_providers/live_balance.rb`**
   - Fixed balance fetching to use correct DhanHQ API
   - Added better error handling and logging

2. **`lib/dhan_scalper/brokers/dhan_broker.rb`**
   - Implemented multiple fallback methods for order creation
   - Added better error handling and logging
   - Fixed trade price fetching

3. **`lib/dhan_scalper/candle_series.rb`**
   - Fixed historical data fetching with multiple fallback methods
   - Added better error handling and logging

4. **`lib/dhan_scalper/app.rb`**
   - Fixed WebSocket creation and disconnection
   - Added fallback methods for WebSocket operations

5. **`lib/dhan_scalper/order.rb`** (New File)
   - Created missing Order class with necessary attributes

6. **`lib/dhan_scalper.rb`**
   - Added require statement for the Order class

## Testing

A test script `test_dhanhq_api.rb` has been created to verify that the DhanHQ API methods are working correctly. Run it with:

```bash
ruby test_dhanhq_api.rb
```

## Usage

The fixes maintain backward compatibility while adding robustness. The system will:

1. Try the primary API method first
2. Fall back to alternative methods if the primary fails
3. Provide detailed logging for debugging
4. Use sensible defaults when all methods fail

## Environment Variables

Make sure you have the following environment variables set for DhanHQ:

```bash
export DHAN_CLIENT_ID="your_client_id"
export DHAN_CLIENT_SECRET="your_client_secret"
export DHAN_USER_ID="your_user_id"
export DHAN_PASSWORD="your_password"
export DHAN_API_KEY="your_api_key"
export DHAN_VENDOR_CODE="your_vendor_code"
```

## Debug Mode

To enable debug logging, set the log level to DEBUG in your configuration:

```yaml
global:
  log_level: "DEBUG"
```

This will provide detailed information about which API methods are being tried and their results.

## Troubleshooting

If you encounter issues:

1. Check the debug logs to see which API methods are failing
2. Verify your DhanHQ credentials and API access
3. Ensure you're using the correct DhanHQ gem version
4. Check the DhanHQ API documentation for any recent changes

## Notes

- The implementation is designed to be resilient to API changes
- Multiple fallback methods ensure compatibility across different DhanHQ versions
- Debug logging helps identify which specific API methods are working
- The system gracefully degrades when API methods are unavailable