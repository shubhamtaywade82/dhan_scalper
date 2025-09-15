# frozen_string_literal: true

require 'dhan_scalper/version'
require 'dhan_scalper/config'
require 'dhan_scalper/indicators'

require 'dhan_scalper/candle'
require 'dhan_scalper/indicators_gate'
require 'dhan_scalper/candle_series'
require 'dhan_scalper/support/application_service'
require 'dhan_scalper/support/time_zone'
require 'dhan_scalper/support/money'
require 'dhan_scalper/support/logger'
require 'dhan_scalper/support/validations'
require 'dhan_scalper/exceptions'
require 'dhan_scalper/services/atomic_operations'
require 'dhan_scalper/services/equity_calculator'
require 'dhan_scalper/services/mtm_refresh_service'
require 'dhan_scalper/unified_risk_manager'
require 'dhan_scalper/atomic'
require 'dhan_scalper/indicators/supertrend'
require 'dhan_scalper/indicators/holy_grail'
require 'dhan_scalper/trend_enhanced'
require 'dhan_scalper/order'
require 'dhan_scalper/option_picker'
require 'dhan_scalper/tick_cache'
require 'dhan_scalper/trader'
require 'dhan_scalper/dryrun_app'
require 'dhan_scalper/paper_app'
require 'dhan_scalper/cli'
require 'dhan_scalper/position'
require 'dhan_scalper/quantity_sizer'
require 'dhan_scalper/balance_providers/base'
require 'dhan_scalper/balance_providers/paper_wallet'
require 'dhan_scalper/balance_providers/live_balance'
require 'dhan_scalper/csv_master'
require 'dhan_scalper/brokers/base'
require 'dhan_scalper/brokers/paper_broker'
require 'dhan_scalper/brokers/dhan_broker'
require 'dhan_scalper/state'
require 'dhan_scalper/pnl'
# UI components removed - using simple console output instead
require 'dhan_scalper/services/dhanhq_config'
require 'dhan_scalper/services/market_feed'
require 'dhan_scalper/services/websocket_cleanup'
require 'dhan_scalper/services/rate_limiter'
require 'dhan_scalper/services/historical_data_cache'
require 'dhan_scalper/services/websocket_manager'
require 'dhan_scalper/services/resilient_websocket_manager'
require 'dhan_scalper/services/ltp_fallback'
require 'dhan_scalper/services/order_monitor'
require 'dhan_scalper/services/position_reconciler'
require 'dhan_scalper/services/paper_position_tracker'
require 'dhan_scalper/services/live_position_tracker'
require 'dhan_scalper/services/live_order_manager'
require 'dhan_scalper/risk_manager'
require 'dhan_scalper/ohlc_fetcher'
require 'dhan_scalper/enhanced_position_tracker'
require 'dhan_scalper/session_reporter'

# Stores
require 'dhan_scalper/stores/redis_store'

# Legacy deprecation stubs (non-functional placeholders to preserve public constants)
require 'dhan_scalper/legacy_stubs'

require 'ruby-technical-analysis'
require 'technical-analysis'

module DhanScalper
  # Register global WebSocket cleanup handlers
  Services::WebSocketCleanup.register_cleanup
end
