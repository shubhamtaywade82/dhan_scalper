# frozen_string_literal: true

require "thor"
require "yaml"
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
    option :enhanced, type: :boolean, aliases: "-e", desc: "Use enhanced indicators (Holy Grail, Supertrend)", default: true
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
    option :enhanced, type: :boolean, aliases: "-e", desc: "Use enhanced indicators (Holy Grail, Supertrend)", default: true
    def dryrun
      cfg = Config.load(path: options[:config])
      quiet = options[:quiet]
      enhanced = options[:enhanced]
      DhanHQ.configure_with_env
      DhanHQ.logger.level = Logger::INFO
      App.new(cfg, dryrun: true, quiet: quiet, enhanced: enhanced).start
    end

    desc "paper", "Start paper trading (alias for start -m paper)"
    option :config, type: :string, aliases: "-c"
    option :quiet, type: :boolean, aliases: "-q", desc: "Run in quiet mode (no TTY dashboard)", default: false
    option :enhanced, type: :boolean, aliases: "-e", desc: "Use enhanced indicators (Holy Grail, Supertrend)", default: true
    def paper
      cfg = Config.load(path: options[:config])
      quiet = options[:quiet]
      enhanced = options[:enhanced]
      DhanHQ.configure_with_env
      DhanHQ.logger.level = (cfg.dig("global", "log_level") || "INFO").upcase == "DEBUG" ? Logger::DEBUG : Logger::INFO
      App.new(cfg, mode: :paper, quiet: quiet, enhanced: enhanced).start
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
        puts "#{index + 1}. #{pos[:side]} #{pos[:quantity]} #{pos[:symbol] || pos[:security_id]} | Entry: #{pos[:entry_price]} | Current: #{pos[:current_price]} | P&L: #{pos[:pnl]&.round(2)}"
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
      FileUtils.rm_rf("data") if Dir.exist?("data")
      puts "All virtual data cleared."
    end

    desc "dashboard", "Show real-time virtual data dashboard"
    def dashboard
      require_relative "ui/data_viewer"
      UI::DataViewer.new.run
    end
  end
end
