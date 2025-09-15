# frozen_string_literal: true

require 'thor'
require 'yaml'
require 'logger'
require 'DhanHQ'

require_relative 'virtual_data_manager'
require_relative 'services/cli_services'
require_relative 'runners/app_runner'
require_relative 'runners/paper_runner'

module DhanScalper
  class CLI < Thor
    def self.exit_on_failure?
      false
    end

    desc 'help', 'Show this help message'
    def help
      puts 'DhanScalper - Automated Options Scalping Bot'
      puts '=' * 50
      puts
      puts 'Commands:'
      # Keep CLI surface small; advanced commands remain available but are hidden from this help summary.
      commands = [
        ['start', 'Start the scalper (Ctrl+C to stop)'],
        ['paper', 'Start paper trading (alias for start -m paper)'],
        ['live', 'Start live trading with real money'],
        ['dryrun', 'Run signals only, no orders'],
        ['orders', 'Show order history'],
        ['positions', 'Show open positions'],
        ['balance', 'Show current balance'],
        ['reset-balance', 'Reset virtual balance to initial amount'],
        ['clear-data', 'Clear all virtual data (orders, positions, balance)'],
        ['config', 'Show DhanHQ configuration status'],
        ['version', 'Show version'],
        ['help', 'Show this help']
      ]
      commands.each { |name, desc| puts format('  %-15s - %s', name, desc) }
      puts
      puts 'Options:'
      options = [
        ['-q, --quiet', 'Run in quiet mode (minimal output)'],
        ['-e, --enhanced', 'Use enhanced indicators (Holy Grail, Supertrend) [default: true]'],
        ['-c, --config', 'Path to configuration file'],
        ['-m, --mode', 'Trading mode (live/paper)']
      ]
      options.each { |opt, desc| puts format('  %-15s - %s', opt, desc) }
      puts
      puts 'For detailed help on a command, use: scalper help COMMAND'
    end

    desc 'start', 'Start the scalper (Ctrl+C to stop)'
    option :config, type: :string, aliases: '-c', desc: 'Path to scalper.yml'
    option :mode, aliases: '-m', desc: 'Trading mode (live/paper)', default: 'paper'
    option :quiet, type: :boolean, aliases: '-q', desc: 'Run in quiet mode (minimal output)', default: false
    option :enhanced, type: :boolean, aliases: '-e', desc: 'Use enhanced indicators (Holy Grail, Supertrend)',
                      default: true
    def start(*_argv)
      opts = respond_to?(:options) && options ? options : {}
      cfg = Config.load(path: opts[:config])
      mode = (opts[:mode] || 'paper').to_sym
      quiet = !opts[:quiet].nil?
      enhanced = opts.key?(:enhanced) ? opts[:enhanced] : true

      # Ensure global WebSocket cleanup is registered
      DhanScalper::Services::WebSocketCleanup.register_cleanup

      # Initialize logger
      DhanScalper::Support::Logger.setup(level: quiet ? :warn : :info)

      DhanHQ.configure_with_env
      # Always set INFO level for CLI start; keep logs concise for terminal usage
      if DhanHQ.respond_to?(:logger)
        logger_obj = DhanHQ.logger
        logger_obj.level = Logger::INFO if logger_obj.respond_to?(:level=)
      end

      # Use the appropriate runner based on mode
      runner = if mode == :paper
                 Runners::PaperRunner.new(cfg, quiet: quiet, enhanced: enhanced)
               else
                 Runners::AppRunner.new(cfg, mode: mode, quiet: quiet, enhanced: enhanced)
               end

      runner.start
    end

    desc 'dryrun', 'Run signals only, no orders'
    option :config, type: :string, aliases: '-c', default: 'config/scalper.yml'
    option :quiet, type: :boolean, aliases: '-q', desc: 'Run in quiet mode (minimal output)', default: false
    option :enhanced, type: :boolean, aliases: '-e', desc: 'Use enhanced indicators (Holy Grail, Supertrend)',
                      default: true
    option :once, type: :boolean, aliases: '-o', desc: 'Run analysis once and exit (no continuous loop)', default: false
    def dryrun
      cfg = Config.load(path: options[:config])
      quiet = options[:quiet]
      enhanced = options[:enhanced]
      once = options[:once]
      DhanHQ.configure_with_env
      DhanHQ.logger.level = Logger::INFO
      DryrunApp.new(cfg, quiet: quiet, enhanced: enhanced, once: once).start
    end

    desc 'paper', 'Start paper trading with WebSocket position tracking'
    option :config, type: :string, aliases: '-c', default: 'config/scalper.yml'
    option :quiet, type: :boolean, aliases: '-q', desc: 'Run in quiet mode (minimal output)', default: false
    option :enhanced, type: :boolean, aliases: '-e', desc: 'Use enhanced indicators (Holy Grail, Supertrend)',
                      default: true
    option :timeout, type: :numeric, aliases: '-t', desc: 'Auto-exit after specified minutes (default: no timeout)'
    def paper
      cfg = Config.load(path: options[:config])
      quiet = options[:quiet]
      enhanced = options[:enhanced]
      timeout_minutes = options[:timeout]

      # Ensure global WebSocket cleanup is registered
      DhanScalper::Services::WebSocketCleanup.register_cleanup

      DhanHQ.configure_with_env
      DhanHQ.logger.level = (cfg.dig('global', 'log_level') || 'INFO').upcase == 'DEBUG' ? Logger::DEBUG : Logger::INFO

      runner = Runners::PaperRunner.new(cfg, quiet: quiet, enhanced: enhanced, timeout_minutes: timeout_minutes)
      runner.start
    end

    desc 'live', 'Start live trading with real money'
    option :config, type: :string, aliases: '-c', default: 'config/scalper.yml'
    option :quiet, type: :boolean, aliases: '-q', desc: 'Run in quiet mode (minimal output)', default: false
    option :enhanced, type: :boolean, aliases: '-e', desc: 'Use enhanced indicators (Holy Grail, Supertrend)',
                      default: true
    def live
      cfg = Config.load(path: options[:config])
      quiet = options[:quiet]
      enhanced = options[:enhanced]

      # Ensure global WebSocket cleanup is registered
      DhanScalper::Services::WebSocketCleanup.register_cleanup

      # Initialize logger
      DhanScalper::Support::Logger.setup(level: quiet ? :warn : :info)

      DhanHQ.configure_with_env
      # Always set INFO level for CLI live; keep logs concise for terminal usage
      if DhanHQ.respond_to?(:logger)
        logger_obj = DhanHQ.logger
        logger_obj.level = Logger::INFO if logger_obj.respond_to?(:level=)
      end

      runner = Runners::AppRunner.new(cfg, mode: :live, quiet: quiet, enhanced: enhanced)
      runner.start
    end

    desc 'orders', 'View virtual orders'
    option :limit, aliases: '-l', desc: 'Number of orders to show', type: :numeric, default: 10
    option :mode, aliases: '-m', desc: 'Trading mode (paper/live)', type: :string, default: 'paper'
    option :format, aliases: '-f', desc: 'Output format (table/json)', type: :string, default: 'table'
    def orders
      mode = options[:mode]&.downcase || 'paper'
      limit = options[:limit]
      format = options[:format]

      service = Services::OrdersService.new(format: format)
      service.display_orders(mode: mode, limit: limit)
    end

    desc 'positions', 'View virtual positions'
    option :mode, aliases: '-m', desc: 'Trading mode (paper/live)', type: :string, default: 'paper'
    option :format, aliases: '-f', desc: 'Output format (table/json)', type: :string, default: 'table'
    def positions
      mode = options[:mode]&.downcase || 'paper'
      format = options[:format]

      service = Services::PositionsService.new(format: format)
      service.display_positions(mode: mode)
    end

    desc 'balance', 'View virtual balance'
    option :mode, aliases: '-m', desc: 'Trading mode (paper/live)', type: :string, default: 'paper'
    option :format, aliases: '-f', desc: 'Output format (table/json)', type: :string, default: 'table'
    def balance
      mode = options[:mode]&.downcase || 'paper'
      format = options[:format]

      service = Services::BalanceService.new(format: format)
      service.display_balance(mode: mode)
    end

    desc 'reset-balance', 'Reset virtual balance to initial amount'
    option :amount, aliases: '-a', desc: 'Initial balance amount', type: :numeric, default: 100_000
    def reset_balance
      amount = options[:amount]
      service = Services::BalanceService.new
      service.reset_balance(amount: amount)
    end

    desc 'clear-data', 'Clear all virtual data (orders, positions, balance)'
    def clear_data
      VirtualDataManager.new
      # This will clear the data directory
      FileUtils.rm_rf('data')
      puts 'All virtual data cleared.'
    end

    desc 'live-data', 'Show live LTP data with WebSocket feed'
    option :interval, type: :numeric, default: 1.0, desc: 'Refresh interval (seconds)'
    option :instruments, type: :string,
                         desc: 'Comma-separated list of instruments (format: name:segment:security_id)'
    def live_data
      # Ensure global WebSocket cleanup is registered
      DhanScalper::Services::WebSocketCleanup.register_cleanup

      instruments = parse_instruments(options[:instruments])

      # Simple live data display
      require_relative 'services/market_feed'

      market_feed = DhanScalper::Services::MarketFeed.new(mode: :quote)
      market_feed.start(instruments)

      puts 'Live LTP Data (Press Ctrl+C to stop)'
      puts '=' * 50

      begin
        loop do
          sleep(options[:interval])
          clear_screen
          puts "Live LTP Data - #{Time.now.strftime('%H:%M:%S')}"
          puts '=' * 50

          instruments.each do |instrument|
            ltp = market_feed.ltp(instrument[:segment], instrument[:security_id])
            puts "#{instrument[:name]}: #{ltp ? "₹#{ltp}" : 'N/A'}"
          end

          puts "\nPress Ctrl+C to stop"
        end
      rescue Interrupt
        puts "\nStopping live data feed..."
      ensure
        market_feed.stop
      end
    end

    desc 'version', 'Show version'
    map %w[-v --version] => :version
    def version
      puts DhanScalper::VERSION
    end

    private

    def clear_screen
      system('clear') || system('cls')
    end

    desc 'report', 'Generate session report from CSV data'
    option :session_id, type: :string, desc: 'Specific session ID to report on'
    option :latest, type: :boolean, aliases: '-l', desc: 'Generate report for latest session', default: false
    def report
      require_relative 'services/session_reporter'

      reporter = Services::SessionReporter.new

      if options[:session_id]
        reporter.generate_report_for_session(options[:session_id])
      elsif options[:latest]
        reporter.generate_latest_session_report
      else
        # List available sessions
        sessions = reporter.list_available_sessions

        if sessions.empty?
          puts 'No session reports found in data/reports/ directory'
          return
        end

        puts 'Available Sessions:'
        puts '=' * 50
        sessions.each do |session|
          puts "#{session[:session_id]} - #{session[:created]} (#{session[:size]} bytes)"
        end
        puts
        puts 'Use: dhan_scalper report --session-id SESSION_ID'
        puts 'Or: dhan_scalper report --latest'
      end
    end

    desc 'status', 'Show key runtime health from Redis'
    def status
      require_relative 'stores/redis_store'

      # Initialize Redis store
      redis_store = DhanScalper::Stores::RedisStore.new(
        namespace: 'dhan_scalper:v1',
        logger: Logger.new($stdout)
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
        total_pnl = session_pnl&.dig('total_pnl') || 0.0

        # Get heartbeat status
        heartbeat = redis_store.get_heartbeat
        heartbeat_status = heartbeat ? '✓ Active' : '✗ Inactive'

        # Get Redis connection status
        redis_status = redis_store.redis.ping == 'PONG' ? '✓ Connected' : '✗ Disconnected'

        puts 'DhanScalper Runtime Health:'
        puts '=========================='
        puts "Redis Status: #{redis_status}"
        puts "Subscriptions: #{subs_count} active"
        puts "Open Positions: #{positions_count}"
        puts "Session PnL: ₹#{total_pnl.round(2)}"
        puts "Heartbeat: #{heartbeat_status}"
        puts "Timestamp: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
      rescue StandardError => e
        puts "Error retrieving status: #{e.message}"
        exit 1
      ensure
        redis_store.disconnect
      end
    end

    desc 'export', 'Export CSV data from Redis history'
    option :since, type: :string, desc: 'Export data since date (YYYY-MM-DD format)', required: true
    def export
      require_relative 'stores/redis_store'
      require 'csv'
      require 'date'

      # Parse since date
      begin
        since_date = Date.parse(options[:since])
        since_timestamp = since_date.to_time.to_i
      rescue ArgumentError
        puts 'Error: Invalid date format. Use YYYY-MM-DD'
        exit 1
      end

      # Initialize Redis store
      redis_store = DhanScalper::Stores::RedisStore.new(
        namespace: 'dhan_scalper:v1',
        logger: Logger.new($stdout)
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
          tick_timestamp = tick_info['ts']&.to_i
          next unless tick_timestamp && tick_timestamp >= since_timestamp

          # Parse key to get segment and security_id
          key_parts = key.split(':')
          segment = key_parts[-2]
          security_id = key_parts[-1]

          tick_data << {
            timestamp: Time.at(tick_timestamp).strftime('%Y-%m-%d %H:%M:%S'),
            segment: segment,
            security_id: security_id,
            ltp: tick_info['ltp'],
            day_high: tick_info['day_high'],
            day_low: tick_info['day_low'],
            atp: tick_info['atp'],
            volume: tick_info['vol']
          }
        end

        # Sort by timestamp
        tick_data.sort_by! { |tick| tick[:timestamp] }

        # Generate CSV
        csv_filename = "export_#{since_date.strftime('%Y%m%d')}_#{Time.now.strftime('%H%M%S')}.csv"

        CSV.open(csv_filename, 'w') do |csv|
          csv << ['Timestamp', 'Segment', 'Security ID', 'LTP', 'Day High', 'Day Low', 'ATP', 'Volume']
          tick_data.each do |tick|
            csv << [
              tick[:timestamp],
              tick[:segment],
              tick[:security_id],
              tick[:ltp],
              tick[:day_high],
              tick[:day_low],
              tick[:atp],
              tick[:volume]
            ]
          end
        end

        puts 'Export completed:'
        puts "  File: #{csv_filename}"
        puts "  Records: #{tick_data.size}"
        puts "  Since: #{since_date.strftime('%Y-%m-%d')}"
        puts "  Period: #{tick_data.first&.dig(:timestamp)} to #{tick_data.last&.dig(:timestamp)}"
      rescue StandardError => e
        puts "Error during export: #{e.message}"
        exit 1
      ensure
        redis_store.disconnect
      end
    end

    desc 'config', 'Show DhanHQ configuration status'
    def config
      require_relative 'services/dhanhq_config'
      status = DhanScalper::Services::DhanHQConfig.status

      puts 'DhanHQ Configuration Status:'
      puts '============================'
      puts "Client ID: #{status[:client_id_present] ? '✓ Set' : '✗ Missing'}"
      puts "Access Token: #{status[:access_token_present] ? '✓ Set' : '✗ Missing'}"
      puts "Base URL: #{status[:base_url]}"
      puts "Log Level: #{status[:log_level]}"
      puts "Configured: #{status[:configured] ? '✓ Yes' : '✗ No'}"

      return if status[:configured]

      puts "\nTo configure, create a .env file with:"
      puts DhanScalper::Services::DhanHQConfig.sample_env
    end

    def parse_instruments(instruments_str)
      return nil unless instruments_str

      instruments_str.split(',').map do |instrument|
        parts = instrument.strip.split(':')
        unless parts.length == 3
          raise ArgumentError, "Invalid instrument format: #{instrument}. Expected: name:segment:security_id"
        end

        { name: parts[0], segment: parts[1], security_id: parts[2] }
      end
    end
  end
end
