To start the scalper for live analysis and scalping, you have several options depending on your needs:

## 🚀 **Live Trading Commands:**

### **1. Live Trading with Enhanced Indicators (Recommended):**
```bash
bundle exec exe/dhan_scalper start -c config/scalper.yml -m live -e
```
- `-m live`: Live trading mode (real money)
- `-e`: Enhanced indicators (Holy Grail + Supertrend)
- `-c config/scalper.yml`: Your configuration file

### **2. Live Trading with TTY Dashboard:**
```bash
bundle exec exe/dhan_scalper start -c config/scalper.yml -m live -e
```
- Shows real-time TTY dashboard with live data

### **3. Live Trading in Quiet Mode (Better for Terminals):**
```bash
bundle exec exe/dhan_scalper start -c config/scalper.yml -m live -e -q
```
- `-q`: Quiet mode (no TTY dashboard, better for terminals)
- Logs to console instead

## 📊 **Paper Trading Commands (Recommended for Testing):**

### **4. Paper Trading with Enhanced Indicators:**
```bash
bundle exec exe/dhan_scalper start -c config/scalper.yml -m paper -e
```
- `-m paper`: Paper trading mode (virtual money)
- Safe for testing strategies

### **5. Paper Trading in Quiet Mode:**
```bash
bundle exec exe/dhan_scalper start -c config/scalper.yml -m paper -e -q
```

## 🔍 **Analysis-Only Commands:**

### **6. Dry Run (Signals Only, No Orders):**
```bash
bundle exec exe/dhan_scalper dryrun -c config/scalper.yml -e
```
- Shows signals but doesn't place any orders
- Perfect for strategy validation

### **7. Dry Run in Quiet Mode:**
```bash
bundle exec exe/dhan_scalper dryrun -c config/scalper.yml -e -q
```

## ⚙️ **Configuration Options:**

- **`-e`**: Enhanced indicators (Holy Grail + Supertrend) - **RECOMMENDED**
- **`-q`**: Quiet mode (no TTY dashboard)
- **`-c config/scalper.yml`**: Path to your configuration file
- **`-m live`**: Live trading (real money)
- **`-m paper`**: Paper trading (virtual money)

## 🎯 **Recommended Starting Command:**

For **live trading** with enhanced indicators:
```bash
bundle exec exe/dhan_scalper start -c config/scalper.yml -m live -e -q
```

For **testing first** (recommended):
```bash
bundle exec exe/dhan_scalper start -c config/scalper.yml -m paper -e -q
```

## 📋 **What You'll See:**

With enhanced indicators (`-e` flag), you'll get:
- **Holy Grail Analysis**: Bias, momentum, ADX, RSI, MACD
- **Supertrend Signals**: Bullish/bearish trend signals
- **Multi-timeframe Analysis**: 1m and 3m combined signals
- **Dynamic ADX Thresholds**: 10 for 1m, 15 for 3m/5m timeframes

## ⚠️ **Important Notes:**

1. **Start with Paper Trading** to test your strategy
2. **Use `-q` flag** if you're running in a terminal that doesn't support TTY
3. **Enhanced indicators (`-e`)** provide much better analysis than basic indicators
4. **Press Ctrl+C** to stop the scalper
5. **Check your `config/scalper.yml`** file for proper configuration

The enhanced indicators will give you much more sophisticated market analysis compared to the basic EMA/RSI signals!