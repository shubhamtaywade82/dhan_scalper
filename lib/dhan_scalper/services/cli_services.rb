# frozen_string_literal: true

require "json"
require "csv"
require "terminal-table"
require_relative "../virtual_data_manager"
require_relative "session_reporter"

module DhanScalper
  module Services
    # Base class for CLI service objects
    class BaseCLIService
      def initialize(options = {})
        @options = options
        @logger = DhanScalper::Support::Logger
      end

      protected

      def format_currency(amount, precision: 2)
        "₹#{amount.to_f.round(precision)}"
      end

      def format_percentage(value, precision: 2)
        "#{value.to_f.round(precision)}%"
      end

      def format_timestamp(timestamp)
        return "N/A" unless timestamp

        Time.at(timestamp).strftime("%Y-%m-%d %H:%M:%S")
      end

      def create_table(headers, rows, title: nil)
        table = Terminal::Table.new(headings: headers, rows: rows)
        table.title = title if title
        table.style = { border: :unicode }
        table
      end
    end

    # Service for handling orders display
    class OrdersService < BaseCLIService
      def display_orders(mode: "paper", limit: 10)
        case mode.downcase
        when "paper"
          display_paper_orders(limit)
        when "live"
          display_live_orders(limit)
        else
          raise ArgumentError, "Invalid mode: #{mode}. Use 'paper' or 'live'"
        end
      end

      private

      def display_paper_orders(limit)
        orders = read_orders_from_latest_report(limit) || []

        if orders.empty?
          # Fallback to legacy VirtualDataManager
          vdm = VirtualDataManager.new
          orders = vdm.get_orders(limit: limit)
        end

        if orders.empty?
          puts "No orders"
          return
        end

        if @options[:format] == "json"
          display_orders_json(orders)
        else
          display_orders_table(orders)
        end
      end

      def display_live_orders(_limit)
        # For live mode, we would need to implement live order fetching
        # This would require integration with DhanHQ API
        puts "Live orders not yet implemented"
        puts "This would require DhanHQ API integration for order history"
      rescue StandardError => e
        puts "Error fetching live orders: #{e.message}"
      end

      def display_orders_table(orders)
        headers = ["#", "Order ID", "Symbol", "Action", "Quantity", "Price", "Status", "Timestamp"]
        rows = orders.each_with_index.map do |order, index|
          [
            index + 1,
            order[:order_id] || order[:id] || "N/A",
            order[:symbol] || order[:security_id] || order[:sym] || "N/A",
            order[:action] || order[:side] || "N/A",
            order[:quantity] || order[:qty] || "N/A",
            format_currency(order[:price] || order[:avg_price] || order[:ltp] || 0),
            order[:status] || order[:state] || "N/A",
            format_timestamp(order[:timestamp] || order[:ts]),
          ]
        end

        table = create_table(headers, rows, title: "PAPER Orders (Last #{orders.length})")
        puts table
      end

      def display_orders_json(orders)
        formatted_orders = orders.map do |order|
          {
            order_id: order[:order_id] || order[:id],
            symbol: order[:symbol] || order[:security_id] || order[:sym],
            action: order[:action] || order[:side],
            quantity: order[:quantity] || order[:qty],
            price: order[:price] || order[:avg_price] || order[:ltp],
            status: order[:status] || order[:state],
            timestamp: format_timestamp(order[:timestamp] || order[:ts]),
          }
        end

        puts JSON.pretty_generate({ orders: formatted_orders })
      end

      def read_orders_from_latest_report(limit)
        reporter = DhanScalper::Services::SessionReporter.new
        sessions = reporter.list_available_sessions
        return nil if sessions.nil? || sessions.empty?

        # Load latest session JSON
        latest = sessions.first
        report = reporter.generate_report_for_session(latest[:session_id])
        trades = report && report[:trades].is_a?(Array) ? report[:trades] : []
        return nil if trades.empty?

        trades.last(limit).map do |t|
          {
            order_id: t[:order_id] || t[:id],
            symbol: t[:symbol],
            action: t[:side] || t[:action],
            quantity: t[:quantity] || t[:qty],
            price: t[:price] || t[:avg_price],
            status: t[:status] || "COMPLETED",
            timestamp: t[:timestamp],
          }
        end
      rescue StandardError
        nil
      end
    end

    # Service for handling positions display
    class PositionsService < BaseCLIService
      def display_positions(mode: "paper")
        case mode.downcase
        when "paper"
          display_paper_positions
        when "live"
          display_live_positions
        else
          raise ArgumentError, "Invalid mode: #{mode}. Use 'paper' or 'live'"
        end
      end

      private

      def display_paper_positions
        positions = read_positions_from_latest_report || []

        if positions.empty?
          # Fallback to legacy VirtualDataManager
          vdm = VirtualDataManager.new
          positions = vdm.get_positions
        end

        if positions.empty?
          puts "No open positions"
          return
        end

        # Display current balance information
        display_current_balance_info

        if @options[:format] == "json"
          display_positions_json(positions)
        else
          display_positions_table(positions)
        end
      end

      def display_live_positions
        # For live mode, we would need to implement live position fetching
        # This would require integration with DhanHQ API
        puts "Live positions not yet implemented"
        puts "This would require DhanHQ API integration for position data"
      rescue StandardError => e
        puts "Error fetching live positions: #{e.message}"
      end

      def display_current_balance_info
        balance_provider = BalanceProviders::PaperWallet.new
        available = balance_provider.available_balance
        used = balance_provider.used_balance
        total = balance_provider.total_balance
        realized_pnl = balance_provider.realized_pnl

        puts "\nBalance:"
        puts "========================================"
        puts "Available: #{format_currency(available)}"
        puts "Used: #{format_currency(used)}"
        puts "Realized PnL: #{format_currency(realized_pnl)}"
        puts "Total: #{format_currency(total)}"
        puts ""
      end

      def display_positions_table(positions)
        headers = ["#", "Symbol", "Quantity", "Side", "Entry Price", "Current Price", "PnL", "PnL %"]
        rows = positions.each_with_index.map do |pos, index|
          entry_price = pos[:entry_price] || pos[:entry] || 0
          current_price = pos[:current_price] || pos[:ltp] || 0
          pnl = pos[:pnl] || 0
          pnl_pct = entry_price.positive? ? (pnl / entry_price * 100) : 0

          [
            index + 1,
            pos[:symbol] || pos[:security_id] || pos[:sym] || "N/A",
            pos[:quantity] || pos[:qty] || "N/A",
            pos[:side] || "N/A",
            format_currency(entry_price),
            format_currency(current_price),
            format_currency(pnl),
            format_percentage(pnl_pct),
          ]
        end

        table = create_table(headers, rows, title: "PAPER Positions")
        puts table
      end

      def display_positions_json(positions)
        formatted_positions = positions.map do |pos|
          entry_price = pos[:entry_price] || pos[:entry] || 0
          current_price = pos[:current_price] || pos[:ltp] || 0
          pnl = pos[:pnl] || 0
          pnl_pct = entry_price.positive? ? (pnl / entry_price * 100) : 0

          {
            symbol: pos[:symbol] || pos[:security_id] || pos[:sym],
            quantity: pos[:quantity] || pos[:qty],
            side: pos[:side],
            entry_price: entry_price,
            current_price: current_price,
            pnl: pnl,
            pnl_percentage: pnl_pct,
          }
        end

        puts JSON.pretty_generate({ positions: formatted_positions })
      end

      def read_positions_from_latest_report
        reporter = DhanScalper::Services::SessionReporter.new
        sessions = reporter.list_available_sessions
        return nil if sessions.nil? || sessions.empty?

        latest = sessions.first
        # Load report data without displaying it
        report = load_report_data(latest[:session_id])
        positions = report && report[:positions].is_a?(Array) ? report[:positions] : []
        return nil if positions.empty?

        positions.map do |p|
          {
            symbol: p[:symbol],
            quantity: p[:quantity] || p[:qty],
            side: p[:side] || p[:option_type],
            entry_price: p[:entry_price] || 0,
            current_price: p[:current_price] || 0,
            pnl: p[:pnl] || 0,
          }
        end
      rescue StandardError
        nil
      end

      def load_report_data(session_id)
        # Load report data without displaying the console summary
        # Find the actual CSV file with the session ID
        csv_files = Dir.glob(File.join("data/reports", "session_#{session_id}_*.csv"))
        return nil if csv_files.empty?

        csv_file = csv_files.first

        report_data = {}
        positions = []
        in_positions_section = false

        CSV.foreach(csv_file, headers: true) do |row|
          # Check if we're in the positions section
          if row[0] == "Symbol" && row[1] == "Option Type"
            in_positions_section = true
            next
          end

          # Check if we're past the positions section
          if in_positions_section && (row[0].nil? || row[0].empty?)
            in_positions_section = false
            next
          end

          # Parse positions
          if in_positions_section && row[0] && !row[0].empty?
            positions << {
              symbol: row[0],
              option_type: row[1],
              strike: row[2],
              quantity: row[3].to_i,
              entry_price: row[4].to_f,
              current_price: row[5].to_f,
              pnl: row[6].to_f,
              created_at: row[7],
            }
            next
          end

          # Parse other data (skip if not in positions section)
          next if in_positions_section

          # Handle regular metric-value pairs
          if row[0] && row[1]
            report_data[row[0]] = row[1]
          end
        end

        report_data[:positions] = positions

        # Convert string values to appropriate types
        report_data.transform_values do |value|
          next value if value.is_a?(Array) # Skip positions array

          case value
          when /^\d+\.\d+$/
            value.to_f
          when /^\d+$/
            value.to_i
          else
            value
          end
        end

        report_data
      end
    end

    # Service for handling balance display
    class BalanceService < BaseCLIService
      def display_balance(mode: "paper")
        case mode.downcase
        when "paper"
          display_paper_balance
        when "live"
          display_live_balance
        else
          raise ArgumentError, "Invalid mode: #{mode}. Use 'paper' or 'live'"
        end
      end

      def reset_balance(amount: 100_000)
        vdm = VirtualDataManager.new
        vdm.set_initial_balance(amount)
        puts "Balance reset to #{format_currency(amount)}"
      end

      private

      def read_balance_from_latest_report
        reporter = DhanScalper::Services::SessionReporter.new
        sessions = reporter.list_available_sessions
        return nil if sessions.nil? || sessions.empty?

        latest = sessions.first
        report = reporter.generate_report_for_session(latest[:session_id])
        return nil unless report

        {
          ending_balance: report[:ending_balance] || report[:final_balance] || 0,
          total_pnl: report[:total_pnl] || report[:realized_pnl] || 0,
        }
      rescue StandardError
        nil
      end

      def display_paper_balance
        # Use current balance provider for accurate data
        balance_provider = BalanceProviders::PaperWallet.new

        available = balance_provider.available_balance
        used = balance_provider.used_balance
        total = balance_provider.total_balance
        realized_pnl = balance_provider.realized_pnl

        if @options[:format] == "json"
          display_balance_json(available, used, total, realized_pnl)
        else
          display_balance_table(available, used, total, realized_pnl)
        end
      end

      def display_live_balance
        balance_provider = BalanceProviders::LiveBalance.new
        available = balance_provider.available_balance
        used = balance_provider.used_balance
        total = balance_provider.total_balance

        if @options[:format] == "json"
          display_balance_json(available, used, total, 0)
        else
          display_balance_table(available, used, total, 0)
        end
      rescue StandardError => e
        puts "Error fetching live balance: #{e.message}"
        puts "Make sure you're connected to DhanHQ API"
      end

      def display_balance_table(available, used, total, realized_pnl)
        puts "\nBalance:"
        puts "=" * 40
        puts "Available: #{format_currency(available)}"
        puts "Used: #{format_currency(used)}"
        puts "Realized PnL: #{format_currency(realized_pnl)}"
        puts "Total: #{format_currency(total)}"
      end

      def display_balance_json(available, used, total, realized_pnl)
        balance_data = {
          available: available,
          used: used,
          realized_pnl: realized_pnl,
          total: total,
        }
        puts JSON.pretty_generate(balance_data)
      end
    end

    # Service for handling status display
    class StatusService < BaseCLIService
      def display_status
        redis_store = DhanScalper::Stores::RedisStore.new(
          namespace: "dhan_scalper:v1",
          logger: Logger.new($stdout),
        )

        begin
          redis_store.connect
          status_data = gather_status_data(redis_store)

          if @options[:format] == "json"
            display_status_json(status_data)
          else
            display_status_table(status_data)
          end
        rescue StandardError => e
          puts "Error retrieving status: #{e.message}"
          exit 1
        ensure
          redis_store.disconnect
        end
      end

      private

      def gather_status_data(redis_store)
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
        heartbeat_status = heartbeat ? "Active" : "Inactive"

        # Get Redis connection status
        redis_status = redis_store.redis.ping == "PONG" ? "Connected" : "Disconnected"

        {
          redis_status: redis_status,
          subscriptions: subs_count,
          open_positions: positions_count,
          session_pnl: total_pnl,
          heartbeat_status: heartbeat_status,
          timestamp: Time.now.strftime("%Y-%m-%d %H:%M:%S"),
        }
      end

      def display_status_table(status_data)
        puts "DhanScalper Runtime Health:"
        puts "=========================="
        puts "Redis Status: #{status_data[:redis_status]}"
        puts "Subscriptions: #{status_data[:subscriptions]} active"
        puts "Open Positions: #{status_data[:open_positions]}"
        puts "Session PnL: #{format_currency(status_data[:session_pnl])}"
        puts "Heartbeat: #{status_data[:heartbeat_status]}"
        puts "Timestamp: #{status_data[:timestamp]}"
      end

      def display_status_json(status_data)
        puts JSON.pretty_generate(status_data)
      end
    end

    # Service for handling configuration display
    class ConfigService < BaseCLIService
      def display_config
        status = DhanScalper::Services::DhanHQConfig.status

        if @options[:format] == "json"
          display_config_json(status)
        else
          display_config_table(status)
        end

        return if status[:configured]

        puts "\nTo configure, create a .env file with:"
        puts DhanScalper::Services::DhanHQConfig.sample_env
      end

      private

      def display_config_table(status)
        puts "DhanHQ Configuration Status:"
        puts "============================"
        puts "Client ID: #{status[:client_id_present] ? "✓ Set" : "✗ Missing"}"
        puts "Access Token: #{status[:access_token_present] ? "✓ Set" : "✗ Missing"}"
        puts "Base URL: #{status[:base_url]}"
        puts "Log Level: #{status[:log_level]}"
        puts "Configured: #{status[:configured] ? "✓ Yes" : "✗ No"}"
      end

      def display_config_json(status)
        puts JSON.pretty_generate(status)
      end
    end
  end
end
