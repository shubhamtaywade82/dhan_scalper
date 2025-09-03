# frozen_string_literal: true

require "thor"
require "yaml"
require "DhanHQ"

require_relative "virtual_data_manager"
require_relative "ui/live_dashboard"

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
      puts "Available commands:"
      puts "  start           - Start the scalper (Ctrl+C to stop)"
      puts "  paper           - Start paper trading (alias for start -m paper)"
      puts "  dryrun          - Run signals only, no orders"
      puts "  orders          - View virtual orders"
      puts "  positions       - View virtual positions"
      puts "  balance         - View virtual balance"
      puts "  reset-balance   - Reset virtual balance to initial amount"
      puts "  clear-data      - Clear all virtual data (orders, positions, balance)"
      puts "  dashboard       - Show real-time virtual data dashboard"
      puts "  live            - Show live LTP dashboard with WebSocket feed"
      puts "                    Use --simple for basic terminal output"
      puts "  config          - Show DhanHQ configuration status"
      puts "  help            - Show this help message"
      puts
      puts "Options:"
      puts "  -q, --quiet     - Run in quiet mode (no TTY dashboard, better for terminals)"
      puts "  -e, --enhanced  - Use enhanced indicators (Holy Grail, Supertrend) [default: true]"
      puts "  -c, --config    - Path to configuration file"
      puts "  -m, --mode      - Trading mode (live/paper)"
      puts
      puts "For detailed help on a command, use: scalper help COMMAND"
    end

    desc "start", "Start the scalper (Ctrl+C to stop)"
    option :config, type: :string, aliases: "-c", desc: "Path to scalper.yml"
    option :mode, aliases: "-m", desc: "Trading mode (live/paper)", default: "paper"
    option :quiet, type: :boolean, aliases: "-q", desc: "Run in quiet mode (no TTY dashboard)", default: false
    option :enhanced, type: :boolean, aliases: "-e", desc: "Use enhanced indicators (Holy Grail, Supertrend)",
                      default: true
    def start
      cfg = Config.load(path: options[:config])
      mode = options[:mode].to_sym
      quiet = options[:quiet]
      enhanced = options[:enhanced]
      DhanHQ.configure_with_env
      DhanHQ.logger.level = (cfg.dig("global", "log_level") || "INFO").upcase == "DEBUG" ? Logger::DEBUG : Logger::INFO
      App.new(cfg, mode: mode, quiet: quiet, enhanced: enhanced).start
    end

    desc "dryrun", "Run signals only, no orders"
    option :config, type: :string, aliases: "-c"
    option :quiet, type: :boolean, aliases: "-q", desc: "Run in quiet mode (no TTY dashboard)", default: false
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

    desc "paper", "Start paper trading with WebSocket position tracking"
    option :config, type: :string, aliases: "-c"
    option :quiet, type: :boolean, aliases: "-q", desc: "Run in quiet mode (no TTY dashboard)", default: false
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
    def orders
      vdm = VirtualDataManager.new
      orders = vdm.get_orders(limit: options[:limit])

      if orders.empty?
        puts "No orders found."
        return
      end

      puts "\nVirtual Orders (Last #{orders.length}):"
      puts "=" * 80
      orders.each_with_index do |order, index|
        puts "#{index + 1}. ID: #{order[:id]} | #{order[:side]} #{order[:quantity]} @ #{order[:avg_price]} | #{order[:timestamp]}"
      end
    end

    desc "positions", "View virtual positions"
    def positions
      vdm = VirtualDataManager.new
      positions = vdm.get_positions

      if positions.empty?
        puts "No positions found."
        return
      end

      puts "\nVirtual Positions:"
      puts "=" * 80
      positions.each_with_index do |pos, index|
        pnl_value = pos[:pnl].is_a?(Numeric) ? pos[:pnl].round(2) : pos[:pnl]
        puts "#{index + 1}. #{pos[:side]} #{pos[:quantity]} #{pos[:symbol] || pos[:security_id]} | Entry: #{pos[:entry_price]} | Current: #{pos[:current_price]} | P&L: #{pnl_value}"
      end
    end

    desc "balance", "View virtual balance"
    def balance
      vdm = VirtualDataManager.new
      balance = vdm.get_balance

      puts "\nVirtual Balance:"
      puts "=" * 40
      puts "Available: ₹#{balance[:available].round(2)}"
      puts "Used: ₹#{balance[:used].round(2)}"
      puts "Total: ₹#{balance[:total].round(2)}"
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

    desc "dashboard", "Show real-time virtual data dashboard"
    def dashboard
      require_relative "ui/data_viewer"
      UI::DataViewer.new.run
    end

    desc "live", "Show live LTP dashboard with WebSocket feed"
    option :interval, type: :numeric, default: 0.5, desc: "Refresh interval (seconds)"
    option :instruments, type: :string,
                        desc: "Comma-separated list of instruments (format: name:segment:security_id)"
    option :simple, type: :boolean, default: false, desc: "Use simple dashboard (no full screen control)"
    def live
      # Ensure global WebSocket cleanup is registered
      DhanScalper::Services::WebSocketCleanup.register_cleanup

      instruments = parse_instruments(options[:instruments])

      if options[:simple]
        require_relative "ui/simple_dashboard"
        UI::SimpleDashboard.new(refresh: options[:interval], instruments: instruments).run
      else
        UI::LiveDashboard.new(refresh: options[:interval], instruments: instruments).run
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

    private

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
