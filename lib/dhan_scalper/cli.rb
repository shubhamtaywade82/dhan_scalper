# frozen_string_literal: true

require "thor"
require "yaml"
require "logger"
require "DhanHQ"

require_relative "virtual_data_manager"

module DhanScalper
  class CLI < Thor
    def self.exit_on_failure?
      false
    end

    desc "help", "Show this help message"
    def help
      puts "DhanScalper - Automated Options Scalping Bot"
      puts "=" * 50
      puts
      puts "Commands:"
      puts "  start           - Start the scalper (Ctrl+C to stop)"
      puts "  paper           - Start paper trading (alias for start -m paper)"
      puts "  headless        - Run headless options buying bot"
      puts "  dryrun          - Run signals only, no orders"
      puts "  orders          - Show order history"
      puts "  positions       - Show open positions"
      puts "  balance         - Show current balance"
      puts "  reset-balance   - Reset virtual balance to initial amount"
      puts "  clear-data      - Clear all virtual data (orders, positions, balance)"
      puts "  live            - Show live LTP data with WebSocket feed"
      puts "  report          - Generate session report from CSV data"
      puts "  status          - Show key runtime health from Redis"
      puts "  export          - Export CSV data from Redis history"
      puts "  config          - Show DhanHQ configuration status"
      puts "  help            - Show this help"
      puts
      puts "Options:"
      puts "  -q, --quiet     - Run in quiet mode (minimal output)"
      puts "  -e, --enhanced  - Use enhanced indicators (Holy Grail, Supertrend) [default: true]"
      puts "  -c, --config    - Path to configuration file"
      puts "  -m, --mode      - Trading mode (live/paper)"
      puts
      puts "For detailed help on a command, use: scalper help COMMAND"
    end

    desc "start", "Start the scalper (Ctrl+C to stop)"
    option :config, type: :string, aliases: "-c", desc: "Path to scalper.yml"
    option :mode, aliases: "-m", desc: "Trading mode (live/paper)", default: "paper"
    option :quiet, type: :boolean, aliases: "-q", desc: "Run in quiet mode (minimal output)", default: false
    option :enhanced, type: :boolean, aliases: "-e", desc: "Use enhanced indicators (Holy Grail, Supertrend)",
                      default: true
    def start(*_argv)
      opts = respond_to?(:options) && options ? options : {}
      cfg = Config.load(path: opts[:config])
      mode = (opts[:mode] || "paper").to_sym
      quiet = !opts[:quiet].nil?
      enhanced = opts.key?(:enhanced) ? opts[:enhanced] : true

      # Initialize logger
      DhanScalper::Support::Logger.setup(level: quiet ? :warn : :info)

      DhanHQ.configure_with_env
      # Always set INFO level for CLI start; keep logs concise for terminal usage
      if DhanHQ.respond_to?(:logger)
        logger_obj = DhanHQ.logger
        logger_obj.level = Logger::INFO if logger_obj.respond_to?(:level=)
      end
      app = App.new(cfg, mode: mode, quiet: quiet, enhanced: enhanced)
      app.start if app.respond_to?(:start)
    end

    desc "dryrun", "Run signals only, no orders"
    option :config, type: :string, aliases: "-c"
    option :quiet, type: :boolean, aliases: "-q", desc: "Run in quiet mode (minimal output)", default: false
    option :enhanced, type: :boolean, aliases: "-e", desc: "Use enhanced indicators (Holy Grail, Supertrend)",
                      default: true
    option :once, type: :boolean, aliases: "-o", desc: "Run analysis once and exit (no continuous loop)", default: false
    def dryrun
      cfg = Config.load(path: options[:config])
      quiet = options[:quiet]
      enhanced = options[:enhanced]
      once = options[:once]
      DhanHQ.configure_with_env
      DhanHQ.logger.level = Logger::INFO
      DryrunApp.new(cfg, quiet: quiet, enhanced: enhanced, once: once).start
    end

    desc "event-driven", "Start event-driven trading with atomic state management"
    option :config, type: :string, aliases: "-c"
    option :quiet, type: :boolean, aliases: "-q", desc: "Run in quiet mode (minimal output)", default: false
    option :enhanced, type: :boolean, aliases: "-e", desc: "Use enhanced indicators (Holy Grail, Supertrend)",
                      default: true
    option :timeout, type: :numeric, aliases: "-t", desc: "Auto-exit after specified minutes (default: no timeout)"
    def event_driven
      cfg = Config.load(path: options[:config])
      quiet = options[:quiet]
      enhanced = options[:enhanced]
      timeout_minutes = options[:timeout]

      # Initialize logger
      DhanScalper::Support::Logger.setup(level: quiet ? :warn : :info)

      DhanHQ.configure_with_env
      DhanHQ.logger.level = Logger::INFO

      app = EventDrivenApp.new(cfg, quiet: quiet, enhanced: enhanced)

      if timeout_minutes
        # Schedule auto-exit
        Thread.new do
          sleep(timeout_minutes * 60)
          puts "\n[EVENT-DRIVEN] Auto-exiting after #{timeout_minutes} minutes"
          app.stop
        end
      end

      # Handle graceful shutdown
      trap("INT") do
        puts "\n[EVENT-DRIVEN] Shutting down gracefully..."
        app.stop
        exit(0)
      end

      app.start

      # Keep main thread alive
      begin
        while app.running?
          sleep(1)
        end
      rescue Interrupt
        puts "\n[EVENT-DRIVEN] Interrupted, shutting down..."
        app.stop
      end
    end

    desc "paper", "Start paper trading with WebSocket position tracking"
    option :config, type: :string, aliases: "-c"
    option :quiet, type: :boolean, aliases: "-q", desc: "Run in quiet mode (minimal output)", default: false
    option :enhanced, type: :boolean, aliases: "-e", desc: "Use enhanced indicators (Holy Grail, Supertrend)",
                      default: true
    option :timeout, type: :numeric, aliases: "-t", desc: "Auto-exit after specified minutes (default: no timeout)"
    def paper
      cfg = Config.load(path: options[:config])
      quiet = options[:quiet]
      enhanced = options[:enhanced]
      timeout_minutes = options[:timeout]
      DhanHQ.configure_with_env
      DhanHQ.logger.level = (cfg.dig("global", "log_level") || "INFO").upcase == "DEBUG" ? Logger::DEBUG : Logger::INFO
      PaperApp.new(cfg, quiet: quiet, enhanced: enhanced, timeout_minutes: timeout_minutes).start
    end

    desc "orders", "View virtual orders"
    option :limit, aliases: "-l", desc: "Number of orders to show", type: :numeric, default: 10
    option :mode, aliases: "-m", desc: "Trading mode (paper/live)", type: :string, default: "paper"
    def orders
      mode = options[:mode]&.downcase || "paper"

      case mode
      when "paper"
        vdm = VirtualDataManager.new
        orders = vdm.get_orders(limit: options[:limit])

        if orders.empty?
          puts "No paper orders"
          return
        end

        puts "Order ID | Symbol | Action | Quantity | Price | Status | Timestamp"
        puts "\nPAPER Orders (Last #{orders.length}):"
        puts "=" * 80
        orders.each_with_index do |order, index|
          order_id = order[:order_id] || order[:id]
          symbol = order[:symbol] || order[:security_id] || order[:sym]
          action = order[:action] || order[:side]
          quantity = order[:quantity] || order[:qty]
          price = order[:price] || order[:avg_price] || order[:ltp]
          status = order[:status] || order[:state]
          timestamp = order[:timestamp] || order[:ts]
          puts "#{index + 1}. #{order_id} | #{symbol} | #{action} | #{quantity} | #{price} | #{status} | #{timestamp}"
        end

      when "live"
        begin
          # For live mode, we would need to implement live order fetching
          # This would require integration with DhanHQ API
          puts "Live orders not yet implemented"
          puts "This would require DhanHQ API integration for order history"
        rescue StandardError => e
          puts "Error fetching live orders: #{e.message}"
        end

      else
        puts "Invalid mode: #{mode}. Use 'paper' or 'live'"
        exit 1
      end
    end

    desc "positions", "View virtual positions"
    option :mode, aliases: "-m", desc: "Trading mode (paper/live)", type: :string, default: "paper"
    def positions
      mode = options[:mode]&.downcase || "paper"

      case mode
      when "paper"
        vdm = VirtualDataManager.new
        positions = vdm.get_positions

        if positions.empty?
          puts "No open paper positions"
          return
        end

        puts "Symbol | Quantity | Side | Entry Price | Current Price | PnL"
        puts "\nPAPER Positions:"
        puts "=" * 80
        positions.each_with_index do |pos, index|
          symbol = pos[:symbol] || pos[:security_id] || pos[:sym]
          quantity = pos[:quantity] || pos[:qty]
          side = pos[:side]
          entry_price = pos[:entry_price] || pos[:entry]
          current_price = pos[:current_price] || pos[:ltp]
          pnl_value = pos[:pnl].is_a?(Numeric) ? pos[:pnl].round(2) : pos[:pnl]
          puts "#{index + 1}. #{symbol} | #{quantity} | #{side} | #{entry_price} | #{current_price} | #{pnl_value}"
        end

      when "live"
        begin
          # For live mode, we would need to implement live position fetching
          # This would require integration with DhanHQ API
          puts "Live positions not yet implemented"
          puts "This would require DhanHQ API integration for position data"
        rescue StandardError => e
          puts "Error fetching live positions: #{e.message}"
        end

      else
        puts "Invalid mode: #{mode}. Use 'paper' or 'live'"
        exit 1
      end
    end

    desc "balance", "View virtual balance"
    option :mode, aliases: "-m", desc: "Trading mode (paper/live)", type: :string, default: "paper"
    def balance
      mode = options[:mode]&.downcase || "paper"

      puts "\n#{mode.upcase} Balance:"
      puts "=" * 40

      case mode
      when "paper"
        # Use VirtualDataManager for paper mode
        vdm = VirtualDataManager.new
        balance = nil
        begin
          balance = vdm.get_balance
        rescue Exception
          balance = nil
        end

        if balance.is_a?(Numeric)
          puts balance
        elsif balance
          available = balance[:available] || balance["available"]
          used = balance[:used] || balance["used"]
          total = balance[:total] || balance["total"]
          puts "Available: ₹#{available.to_f.round(2)}"
          puts "Used: ₹#{used.to_f.round(2)}"
          puts "Total: ₹#{total.to_f.round(2)}"
        else
          puts "0.0"
        end

      when "live"
        # Use LiveBalance for live mode
        begin
          balance_provider = BalanceProviders::LiveBalance.new
          puts "Available: ₹#{balance_provider.available_balance.round(2)}"
          puts "Used: ₹#{balance_provider.used_balance.round(2)}"
          puts "Total: ₹#{balance_provider.total_balance.round(2)}"
        rescue StandardError => e
          puts "Error fetching live balance: #{e.message}"
          puts "Make sure you're connected to DhanHQ API"
        end

      else
        puts "Invalid mode: #{mode}. Use 'paper' or 'live'"
        exit 1
      end
    end

    desc "reset-balance", "Reset virtual balance to initial amount"
    option :amount, aliases: "-a", desc: "Initial balance amount", type: :numeric, default: 100_000
    def reset_balance
      vdm = VirtualDataManager.new
      vdm.set_initial_balance(options[:amount])
      puts "Balance reset to ₹#{options[:amount]}"
    end

    desc "clear-data", "Clear all virtual data (orders, positions, balance)"
    def clear_data
      VirtualDataManager.new
      # This will clear the data directory
      FileUtils.rm_rf("data")
      puts "All virtual data cleared."
    end

    desc "live", "Show live LTP data with WebSocket feed"
    option :interval, type: :numeric, default: 1.0, desc: "Refresh interval (seconds)"
    option :instruments, type: :string,
                         desc: "Comma-separated list of instruments (format: name:segment:security_id)"
    def live
      # Ensure global WebSocket cleanup is registered
      DhanScalper::Services::WebSocketCleanup.register_cleanup

      instruments = parse_instruments(options[:instruments])

      # Simple live data display
      require_relative "services/market_feed"

      market_feed = DhanScalper::Services::MarketFeed.new(mode: :quote)
      market_feed.start(instruments)

      puts "Live LTP Data (Press Ctrl+C to stop)"
      puts "=" * 50

      begin
        loop do
          sleep(options[:interval])
          clear_screen
          puts "Live LTP Data - #{Time.now.strftime("%H:%M:%S")}"
          puts "=" * 50

          instruments.each do |instrument|
            ltp = market_feed.ltp(instrument[:segment], instrument[:security_id])
            puts "#{instrument[:name]}: #{ltp ? "₹#{ltp}" : "N/A"}"
          end

          puts "\nPress Ctrl+C to stop"
        end
      rescue Interrupt
        puts "\nStopping live data feed..."
      ensure
        market_feed.stop
      end
    end

    private

    def clear_screen
      system("clear") || system("cls")
    end

    desc "headless", "Run headless options buying bot"
    option :config, type: :string, aliases: "-c", desc: "Path to scalper.yml", default: "config/scalper.yml"
    option :mode, aliases: "-m", desc: "Trading mode (live/paper)", default: "paper"
    def headless
      require_relative "headless_app"

      cfg = Config.load(path: options[:config])
      mode = options[:mode].to_sym

      app = HeadlessApp.new(cfg, mode: mode)
      app.start
    end

    desc "enhanced", "Start enhanced trading mode with No-Loss Trend Rider"
    option :config, type: :string, aliases: "-c", desc: "Path to enhanced_scalper.yml",
                    default: "config/enhanced_scalper.yml"
    def enhanced
      require_relative "enhanced_app"

      puts "[ENHANCED] Starting enhanced trading mode"
      puts "[ENHANCED] Config: #{options[:config]}"
      puts "[ENHANCED] Features: No-Loss Trend Rider, Advanced Risk Management, Telegram Notifications"

      app = EnhancedApp.new(config_path: options[:config])
      app.start
    end

    desc "report", "Generate session report from CSV data"
    option :session_id, type: :string, desc: "Specific session ID to report on"
    option :latest, type: :boolean, aliases: "-l", desc: "Generate report for latest session", default: false
    def report
      require_relative "services/session_reporter"

      reporter = Services::SessionReporter.new

      if options[:session_id]
        reporter.generate_report_for_session(options[:session_id])
      elsif options[:latest]
        reporter.generate_latest_session_report
      else
        # List available sessions
        sessions = reporter.list_available_sessions

        if sessions.empty?
          puts "No session reports found in data/reports/ directory"
          return
        end

        puts "Available Sessions:"
        puts "=" * 50
        sessions.each do |session|
          puts "#{session[:session_id]} - #{session[:created]} (#{session[:size]} bytes)"
        end
        puts
        puts "Use: dhan_scalper report --session-id SESSION_ID"
        puts "Or: dhan_scalper report --latest"
      end
    end

    desc "status", "Show key runtime health from Redis"
    def status
      require_relative "stores/redis_store"

      # Initialize Redis store
      redis_store = DhanScalper::Stores::RedisStore.new(
        namespace: "dhan_scalper:v1",
        logger: Logger.new($stdout),
      )

      begin
        redis_store.connect

        # Get subscription count
        subs_count = redis_store.redis.keys("#{redis_store.namespace}:ticks:*").size

        # Get open positions count
        open_positions = redis_store.get_open_positions
        positions_count = open_positions.size

        # Get session PnL
        session_pnl = redis_store.get_session_pnl
        total_pnl = session_pnl&.dig("total_pnl") || 0.0

        # Get heartbeat status
        heartbeat = redis_store.get_heartbeat
        heartbeat_status = heartbeat ? "✓ Active" : "✗ Inactive"

        # Get Redis connection status
        redis_status = redis_store.redis.ping == "PONG" ? "✓ Connected" : "✗ Disconnected"

        puts "DhanScalper Runtime Health:"
        puts "=========================="
        puts "Redis Status: #{redis_status}"
        puts "Subscriptions: #{subs_count} active"
        puts "Open Positions: #{positions_count}"
        puts "Session PnL: ₹#{total_pnl.round(2)}"
        puts "Heartbeat: #{heartbeat_status}"
        puts "Timestamp: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}"
      rescue StandardError => e
        puts "Error retrieving status: #{e.message}"
        exit 1
      ensure
        redis_store.disconnect
      end
    end

    desc "export", "Export CSV data from Redis history"
    option :since, type: :string, desc: "Export data since date (YYYY-MM-DD format)", required: true
    def export
      require_relative "stores/redis_store"
      require "csv"
      require "date"

      # Parse since date
      begin
        since_date = Date.parse(options[:since])
        since_timestamp = since_date.to_time.to_i
      rescue ArgumentError
        puts "Error: Invalid date format. Use YYYY-MM-DD"
        exit 1
      end

      # Initialize Redis store
      redis_store = DhanScalper::Stores::RedisStore.new(
        namespace: "dhan_scalper:v1",
        logger: Logger.new($stdout),
      )

      begin
        redis_store.connect

        # Get all tick data since the specified date
        tick_keys = redis_store.redis.keys("#{redis_store.namespace}:ticks:*")
        tick_data = []

        tick_keys.each do |key|
          tick_info = redis_store.redis.hgetall(key)
          next if tick_info.empty?

          # Check if tick is after since_date
          tick_timestamp = tick_info["ts"]&.to_i
          next unless tick_timestamp && tick_timestamp >= since_timestamp

          # Parse key to get segment and security_id
          key_parts = key.split(":")
          segment = key_parts[-2]
          security_id = key_parts[-1]

          tick_data << {
            timestamp: Time.at(tick_timestamp).strftime("%Y-%m-%d %H:%M:%S"),
            segment: segment,
            security_id: security_id,
            ltp: tick_info["ltp"],
            day_high: tick_info["day_high"],
            day_low: tick_info["day_low"],
            atp: tick_info["atp"],
            volume: tick_info["vol"],
          }
        end

        # Sort by timestamp
        tick_data.sort_by! { |tick| tick[:timestamp] }

        # Generate CSV
        csv_filename = "export_#{since_date.strftime("%Y%m%d")}_#{Time.now.strftime("%H%M%S")}.csv"

        CSV.open(csv_filename, "w") do |csv|
          csv << ["Timestamp", "Segment", "Security ID", "LTP", "Day High", "Day Low", "ATP", "Volume"]
          tick_data.each do |tick|
            csv << [
              tick[:timestamp],
              tick[:segment],
              tick[:security_id],
              tick[:ltp],
              tick[:day_high],
              tick[:day_low],
              tick[:atp],
              tick[:volume],
            ]
          end
        end

        puts "Export completed:"
        puts "  File: #{csv_filename}"
        puts "  Records: #{tick_data.size}"
        puts "  Since: #{since_date.strftime("%Y-%m-%d")}"
        puts "  Period: #{tick_data.first&.dig(:timestamp)} to #{tick_data.last&.dig(:timestamp)}"
      rescue StandardError => e
        puts "Error during export: #{e.message}"
        exit 1
      ensure
        redis_store.disconnect
      end
    end

    desc "config", "Show DhanHQ configuration status"
    def config
      require_relative "services/dhanhq_config"
      status = DhanScalper::Services::DhanHQConfig.status

      puts "DhanHQ Configuration Status:"
      puts "============================"
      puts "Client ID: #{status[:client_id_present] ? "✓ Set" : "✗ Missing"}"
      puts "Access Token: #{status[:access_token_present] ? "✓ Set" : "✗ Missing"}"
      puts "Base URL: #{status[:base_url]}"
      puts "Log Level: #{status[:log_level]}"
      puts "Configured: #{status[:configured] ? "✓ Yes" : "✗ No"}"

      return if status[:configured]

      puts "\nTo configure, create a .env file with:"
      puts DhanScalper::Services::DhanHQConfig.sample_env
    end

    def parse_instruments(instruments_str)
      return nil unless instruments_str

      instruments_str.split(",").map do |instrument|
        parts = instrument.strip.split(":")
        unless parts.length == 3
          raise ArgumentError, "Invalid instrument format: #{instrument}. Expected: name:segment:security_id"
        end

        { name: parts[0], segment: parts[1], security_id: parts[2] }
      end
    end

    desc "version", "Show version"
    map %w[-v --version] => :version
    def version
      puts DhanScalper::VERSION
    end
  end
end
