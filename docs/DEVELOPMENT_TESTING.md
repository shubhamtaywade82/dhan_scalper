# DhanScalper Development Testing Guide

This guide explains how to test and develop the dhan_scalper tool locally and in development mode.

## 🚀 Quick Start

### 1. **Setup Development Environment**
```bash
# Run the development setup script
./bin/dev_setup

# This will:
# - Install dependencies
# - Create development config
# - Set up environment variables
# - Run basic tests
```

### 2. **Interactive Console (Recommended for Development)**
```bash
# Start the interactive console
./bin/console

# The console provides:
# - Pre-loaded test objects
# - Sample data
# - Interactive testing environment
```

### 3. **Run Development Tests**
```bash
# Run comprehensive development tests
./bin/dev_test

# This tests all major components:
# - Configuration loading
# - Balance providers
# - Virtual data manager
# - Paper broker
# - Tick cache
# - CLI functionality
```

## 🔧 Development Configuration

### **Development Config File: `config/development.yml`**
```yaml
symbols: ["NIFTY"] # Test with NIFTY only

global:
  log_level: "DEBUG"           # Enable debug logging
  decision_interval: 30        # Slower for development
  max_lots_per_trade: 2       # Reduced for testing
  max_day_loss: 1500          # Conservative limits

paper:
  starting_balance: 100000     # Reduced for testing
```

### **Environment Variables: `.env`**
```bash
# DhanHQ API Credentials (for live testing)
export DHAN_CLIENT_ID="your_client_id"
export DHAN_CLIENT_SECRET="your_client_secret"
export DHAN_USER_ID="your_user_id"
export DHAN_PASSWORD="your_password"
export DHAN_API_KEY="your_api_key"
export DHAN_VENDOR_CODE="your_vendor_code"

# Development settings
export DHAN_SCALPER_ENV="development"
export DHAN_SCALPER_LOG_LEVEL="DEBUG"
```

## 🧪 Testing Different Components

### **1. Paper Trading Mode (Safest for Development)**
```bash
# Test paper trading with development config
./exe/dhan_scalper paper -c config/development.yml

# This will:
# - Use paper wallet (no real money)
# - Load development configuration
# - Enable debug logging
# - Use reduced lot sizes
```

### **2. Dry Run Mode (Signal Testing)**
```bash
# Test trading signals without placing orders
./exe/dhan_scalper dryrun -c config/development.yml

# This will:
# - Run all trading logic
# - Show what trades would be made
# - Not place any actual orders
# - Perfect for strategy testing
```

### **3. Live Trading Mode (Use with Caution)**
```bash
# Only use when you're confident in your setup
./exe/dhan_scalper start -c config/development.yml -m live

# This will:
# - Connect to live DhanHQ API
# - Place real orders
# - Use real money
# - Require proper API credentials
```

## 🎯 Interactive Console Examples

### **Start the Console**
```bash
./bin/console
```

### **Test Basic Components**
```ruby
# View configuration
@config['symbols']
@config.dig('global', 'log_level')

# Test balance providers
@paper_wallet.available_balance
@paper_wallet.update_balance(5000, type: :debit)

# Test virtual data manager
@vdm.get_balance
@vdm.get_orders
@vdm.get_positions

# Test tick cache
DhanScalper::TickCache.ltp('IDX_I', '13')

# Test paper broker
@paper_broker.buy_market(
  segment: 'NSE_FNO', 
  security_id: 'TEST', 
  quantity: 75
)
```

### **Test DhanHQ API (if configured)**
```ruby
# Test balance fetching
begin
  funds = DhanHQ::Models::Funds.fetch
  puts "Available: ₹#{funds.available_balance}"
  puts "Utilized: ₹#{funds.utilized_amount}"
rescue => e
  puts "API Error: #{e.message}"
end

# Test historical data
begin
  data = DhanHQ::Models::HistoricalData.intraday(
    security_id: "13",
    exchange_segment: "IDX_I",
    instrument: "INDEX",
    interval: "1"
  )
  puts "Data: #{data.inspect}"
rescue => e
  puts "Historical Data Error: #{e.message}"
end
```

## 📊 Monitoring and Debugging

### **View Virtual Data Dashboard**
```bash
# Open real-time dashboard
./exe/dhan_scalper dashboard

# This shows:
# - Current positions
# - Order history
# - Balance information
# - Real-time updates
```

### **Check Virtual Orders and Positions**
```bash
# View virtual orders
./exe/dhan_scalper orders

# View virtual positions
./exe/dhan_scalper positions

# Check virtual balance
./exe/dhan_scalper balance
```

### **Debug Logging**
```bash
# Enable debug mode in config
global:
  log_level: "DEBUG"

# Or set environment variable
export DHAN_SCALPER_LOG_LEVEL="DEBUG"
```

## 🚨 Troubleshooting

### **Common Issues and Solutions**

#### **1. DhanHQ API Connection Issues**
```bash
# Check credentials
echo $DHAN_CLIENT_ID
echo $DHAN_CLIENT_SECRET

# Test API connection
ruby test_dhanhq_api.rb
```

#### **2. Configuration Loading Errors**
```bash
# Verify config file exists
ls -la config/development.yml

# Check YAML syntax
ruby -e "require 'yaml'; YAML.load_file('config/development.yml')"
```

#### **3. Balance Provider Issues**
```ruby
# In console, test balance provider
begin
  bp = DhanScalper::BalanceProviders::PaperWallet.new(100_000)
  puts bp.available_balance
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(3)
end
```

#### **4. Broker Issues**
```ruby
# Test broker creation
begin
  broker = DhanScalper::Brokers::PaperBroker.new(
    virtual_data_manager: DhanScalper::VirtualDataManager.new,
    balance_provider: DhanScalper::BalanceProviders::PaperWallet.new(100_000)
  )
  puts "Broker created successfully"
rescue => e
  puts "Broker Error: #{e.message}"
end
```

## 🔄 Development Workflow

### **1. Make Changes**
```bash
# Edit source files
vim lib/dhan_scalper/brokers/dhan_broker.rb
```

### **2. Test Changes**
```bash
# Test in console
./bin/console

# Run development tests
./bin/dev_test

# Test specific functionality
./exe/dhan_scalper paper -c config/development.yml
```

### **3. Debug and Iterate**
```bash
# Enable debug logging
# Check console output
# Use interactive console for testing
# Monitor virtual data dashboard
```

## 📝 Best Practices

### **1. Always Use Paper Mode First**
- Test with paper wallet before live trading
- Verify all logic works correctly
- Check risk management settings

### **2. Use Development Configuration**
- Separate config for development
- Reduced lot sizes and limits
- Longer decision intervals

### **3. Enable Debug Logging**
- Monitor all API calls
- Track order creation and execution
- Debug balance and position updates

### **4. Test Incrementally**
- Test individual components first
- Verify integration points
- Test full workflow end-to-end

### **5. Monitor Virtual Data**
- Use dashboard for real-time monitoring
- Check orders and positions
- Verify balance calculations

## 🎯 Next Steps

1. **Run `./bin/dev_setup`** to set up your development environment
2. **Use `./bin/console`** for interactive testing and development
3. **Test with `./bin/dev_test`** to verify all components work
4. **Start with paper trading** using development configuration
5. **Gradually test live functionality** when ready

Happy developing! 🚀