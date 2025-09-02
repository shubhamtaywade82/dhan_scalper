# frozen_string_literal: true

require "tty-box"
require "tty-table"
require "pastel"
require_relative "../services/market_feed"
require_relative "../tick_cache"

module DhanScalper
  module UI
    # Simple dashboard that doesn't use full screen control
    class SimpleDashboard
      def initialize(refresh: 1.0, instruments: nil, state: nil, balance_provider: nil)
        @refresh = [refresh, 0.5].max # Minimum 0.5 second refresh rate
        @pastel = Pastel.new
        @instruments = instruments || default_instruments
        @market_feed = nil
        @state = state
        @balance_provider = balance_provider
        @show_trading_data = !state.nil?
        @running = true
        setup_cleanup_handlers
      end

      # Run the simple dashboard
      def run
        trap("INT") { stop }
        trap("TERM") { stop }

        begin
          start_market_feed
          puts "Starting Simple Dashboard (Press Ctrl+C to exit)..."
          puts "=" * 60

          while @running
            render_simple_dashboard
            sleep @refresh
          end
        rescue StandardError => e
          puts "Error: #{e.message}"
          puts "Make sure your DhanHQ credentials are configured in .env file"
        ensure
          stop
          puts "\nDashboard stopped."
        end
      end

      private

      def start_market_feed
        @market_feed = DhanScalper::Services::MarketFeed.new(mode: :quote)
        @market_feed.start(@instruments)
      end

      def stop
        @running = false
        @market_feed&.stop
      end

      def setup_cleanup_handlers
        @cleanup_registered ||= begin
          at_exit do
            stop if @running
          end
          true
        end
      end

      def default_instruments
        [
          { name: "NIFTY 50", segment: "IDX_I", security_id: "13" },
          { name: "BANKNIFTY", segment: "IDX_I", security_id: "25" },
          { name: "SENSEX", segment: "IDX_I", security_id: "51" }
        ]
      end

      def render_simple_dashboard
        # Clear previous output with simple line clearing
        print "\r" + " " * 80 + "\r"

        # Header
        puts @pastel.cyan.bold("DHAN SCALPER - LIVE MARKET DATA")
        puts @pastel.dim("Updated: #{Time.now.strftime("%H:%M:%S")}")
        puts

        # Live LTPs
        render_ltp_table

        # Trading data if available
        if @show_trading_data
          puts
          render_trading_data
        end

        # Status
        puts
        render_status

        puts
        puts @pastel.dim("Press Ctrl+C to exit")
        puts "-" * 60
      end

      def render_ltp_table
        puts @pastel.bold("LIVE LTPs:")

        rows = @instruments.map do |instrument|
          name = instrument[:name]
          segment = instrument[:segment]
          security_id = instrument[:security_id]

          ltp = TickCache.ltp(segment, security_id)
          tick = TickCache.get(segment, security_id)

          if ltp
            trend = trend_indicator(ltp, tick)
            age = tick_age(tick)
            status = @pastel.green("●")
            [name, fmt_price(ltp), trend, age, status]
          else
            status = @pastel.red("●")
            [name, "---", "---", "---", status]
          end
        end

        table = TTY::Table.new(
          header: %w[Instrument LTP Trend Age Status],
          rows: rows
        )

        puts table.render(:ascii, padding: [0, 1, 0, 1])
      end

      def render_trading_data
        return unless @state && @balance_provider

        puts @pastel.bold("TRADING DATA:")

        # Balance
        available = @balance_provider.available_balance.to_f.round(0)
        used = @balance_provider.used_balance.to_f.round(0)
        total = @balance_provider.total_balance.to_f.round(0)
        puts "Balance: Available: #{@pastel.green("₹#{available}")} | Used: #{@pastel.red("₹#{used}")} | Total: #{@pastel.blue("₹#{total}")}"

        # Trading status
        status = case @state.status
                 when :running then "RUNNING"
                 when :paused then "PAUSED"
                 else @state.status.to_s.upcase
                 end
        pnl = @state.pnl.to_f
        pnl_s = pnl >= 0 ? "+#{pnl.round(0)}" : pnl.round(0).to_s
        puts "Status: #{status} | Session PnL: #{pnl_s}"

        # Open positions
        if @state.respond_to?(:open) && !@state.open.empty?
          puts "Open Positions: #{@state.open.size}"
        end
      end

      def render_status
        feed_status = @market_feed&.running? ? @pastel.green("CONNECTED") : @pastel.red("DISCONNECTED")
        cache_stats = TickCache.stats
        puts "Feed: #{feed_status} | Cached Ticks: #{cache_stats[:total_ticks]}"
      end

      def fmt_price(v)
        return "---" if v.nil?
        format("%0.2f", v)
      end

      def trend_indicator(ltp, tick = nil)
        return "---" unless ltp

        if tick && tick[:prev_close] && tick[:prev_close] > 0
          prev_close = tick[:prev_close]
          if ltp > prev_close
            @pastel.green("▲")
          elsif ltp < prev_close
            @pastel.red("▼")
          else
            @pastel.yellow("●")
          end
        else
          # Fallback: use last digit for visual indication
          sym = ltp.to_i.even? ? "▲" : "▼"
          color = sym == "▲" ? :green : :red
          @pastel.public_send(color, sym)
        end
      end

      def tick_age(tick)
        return "---" unless tick&.dig(:timestamp)

        age_seconds = (Time.now - tick[:timestamp]).to_i
        case age_seconds
        when 0..1 then "1s"
        when 2..59 then "#{age_seconds}s"
        else "#{age_seconds}s"
        end
      end
    end
  end
end
