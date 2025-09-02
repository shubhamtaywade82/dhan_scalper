# frozen_string_literal: true

require "tty-box"
require "tty-table"
require "tty-font"
require "tty-screen"
require "tty-cursor"
require "tty-reader"
require "pastel"
require_relative "../services/market_feed"
require_relative "../tick_cache"

module DhanScalper
  module UI
    class LiveDashboard
      def initialize(refresh: 0.5, instruments: nil, state: nil, balance_provider: nil)
        @refresh = [refresh, 0.1].max # Minimum 0.1 second refresh rate
        @pastel  = Pastel.new
        @reader  = TTY::Reader.new
        @cursor  = TTY::Cursor
        @font    = TTY::Font.new(:straight) # readable even on smaller terminals
        @running = true
        @instruments = instruments || default_instruments
        @market_feed = nil
        @state = state
        @balance_provider = balance_provider
        @show_trading_data = !state.nil?
        @last_content = nil
        @last_update = Time.at(0)
        @last_timestamp_update = nil
        @cached_timestamp = nil
        setup_cleanup_handlers
      end

      # Run the dashboard with live market data
      def run
        trap_resize!
        trap("INT")  { stop }
        trap("TERM") { stop }

        print @cursor.hide
        print @cursor.clear_screen
        print @cursor.move_to(1, 1)

        begin
          start_market_feed

          while @running
            width = TTY::Screen.width
            height = TTY::Screen.height
            frame = render_frame(width, height)

            # Only update if content has changed or enough time has passed
            if frame != @last_content || (Time.now - @last_update) > 5.0
              # Move cursor to top and clear screen without scrolling
              print @cursor.move_to(1, 1)
              print @cursor.clear_screen_down
              print frame

              @last_content = frame
              @last_update = Time.now
            end

            sleep @refresh
          end
        rescue StandardError => e
          puts "Error: #{e.message}"
          puts "Make sure your DhanHQ credentials are configured in .env file"
        ensure
          stop
          # restore terminal
          print @cursor.show
          print @cursor.clear_screen
          puts
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
        # Set up at_exit handler to ensure WebSocket connections are properly closed
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

      def trap_resize!
        trap("WINCH") do
          # on resize we just trigger next render; loop reads current width/height
        end
      end

      def clear_screen
        "\e[2J\e[H" # clear + cursor home
      end

      def render_frame(width, height)
        content_parts = []

        # Header
        content_parts << render_header(width)

        # Live LTPs section
        content_parts << render_ltp_section(width)

        # Trading data section (if available)
        if @show_trading_data
          content_parts << render_trading_section(width)
        end

        # Status info
        content_parts << render_status_section(width)

        content = content_parts.join("\n\n")

        # Limit content to screen height to prevent scrolling
        max_height = height - 2 # Leave some margin
        content_lines = content.lines

        if content_lines.size > max_height
          # Truncate content if it's too long
          content = content_lines.first(max_height).join
        end

        content
      end

      def render_header(width)
        title = "DHAN SCALPER"
        subtitle = "LIVE MARKET DASHBOARD"

        header_lines = []
        if width >= 72
          header_lines << @pastel.cyan.bold(@font.write(title))
        else
          header_lines << @pastel.cyan.bold(title)
        end
        header_lines << @pastel.dim(subtitle.center(width))

        TTY::Box.frame(
          width: width,
          title: { top_left: " #{title} " },
          style: { border: { fg: :bright_blue } }
        ) { header_lines.join("\n") }
      end

      def render_ltp_section(width)
        rows = @instruments.map do |instrument|
          name = instrument[:name]
          segment = instrument[:segment]
          security_id = instrument[:security_id]

          # Get live LTP from cache
          ltp = TickCache.ltp(segment, security_id)
          tick = TickCache.get(segment, security_id)

          if ltp
            trend = trend_pill(ltp, tick)
            status = @pastel.green("●") # Connected
            age = tick_age(tick)
            [name, fmt_price(ltp), trend, age, status]
          else
            status = @pastel.red("●") # No data
            [name, "---", "---", "---", status]
          end
        end

        table = TTY::Table.new(
          header: %w[Instrument LTP Trend Age Status],
          rows: rows
        )

        table_str = table.render(:unicode, padding: [0, 1, 0, 1]) do |renderer|
          renderer.border_class = TTY::Table::Border::Unicode
          renderer.alignments = %i[left right center center center]
          renderer.column_widths = [[20, width / 5].min, 12, 8, 8, 8]
        end

        TTY::Box.frame(
          width: [width - 4, 30].max,
          title: { top_left: "  LIVE LTPs  " },
          padding: 1,
          border: :thick
        ) { table_str }
      end

      def render_trading_section(width)
        sections = []

        # Balance section
        if @balance_provider
          sections << render_balance_section(width)
        end

        # Positions section
        if @state && @state.respond_to?(:open)
          sections << render_positions_section(width)
        end

        # Closed positions section
        if @state && @state.respond_to?(:closed)
          sections << render_closed_section(width)
        end

        sections.join("\n")
      end

      def render_balance_section(width)
        available = @balance_provider.available_balance.to_f.round(0)
        used = @balance_provider.used_balance.to_f.round(0)
        total = @balance_provider.total_balance.to_f.round(0)

        content = <<~TEXT
        Available: #{@pastel.green("₹#{available}")}   Used: #{@pastel.red("₹#{used}")}   Total: #{@pastel.blue("₹#{total}")}
        TEXT

        TTY::Box.frame(
          width: width,
          title: { top_left: " Balance " },
          style: { border: { fg: :bright_green } }
        ) { content }
      end

      def render_positions_section(width)
        return "" unless @state.respond_to?(:open)

        rows = @state.open.map do |p|
          net = p[:net].to_f
          net_color = net >= 0 ? :green : :red
          [
            p[:symbol],
            p[:side],
            p[:sid],
            p[:qty_lots],
            fmt_price(p[:entry]),
            fmt_price(p[:ltp]),
            @pastel.send(net_color, net.round(0).to_s),
            p[:best].to_f.round(0)
          ]
        end

        table = TTY::Table.new(
          header: ["Symbol","Side","SID","Lots","Entry","LTP","Net₹","Best₹"],
          rows: rows
        )

        content = rows.empty? ? "No open positions" : table.render(:ascii, resize: true)

        TTY::Box.frame(
          width: width,
          title: { top_left: " Open Positions " },
          style: { border: { fg: :bright_black } }
        ) { content }
      end

      def render_closed_section(width)
        return "" unless @state.respond_to?(:closed)

        rows = @state.closed.last(5).reverse.map do |p|
          net = p[:net].to_f
          net_color = net >= 0 ? :green : :red
          [
            p[:symbol],
            p[:side],
            p[:reason],
            fmt_price(p[:entry]),
            fmt_price(p[:exit_price]),
            @pastel.send(net_color, net.round(0).to_s)
          ]
        end

        table = TTY::Table.new(
          header: ["Symbol","Side","Reason","Entry","Exit","Net₹"],
          rows: rows
        )

        content = rows.empty? ? "No recent closed positions" : table.render(:ascii, resize: true)

        TTY::Box.frame(
          width: width,
          title: { top_left: " Recent Closed (5) " },
          style: { border: { fg: :bright_black } }
        ) { content }
      end

      def render_status_section(width)
        feed_status = @market_feed&.running? ? @pastel.green("CONNECTED") : @pastel.red("DISCONNECTED")
        cache_stats = TickCache.stats

        # Only update timestamp every 5 seconds to reduce flickering
        current_time = Time.now
        if @last_timestamp_update.nil? || (current_time - @last_timestamp_update) >= 5
          @last_timestamp_update = current_time
          @cached_timestamp = current_time.strftime("%H:%M:%S")
        end

        status_lines = [
          @pastel.dim("Feed Status: #{feed_status}"),
          @pastel.dim("Cached Ticks: #{cache_stats[:total_ticks]}"),
          @pastel.dim("Updated: #{@cached_timestamp}"),
          @pastel.dim("Press Ctrl+C to exit")
        ]

        if @show_trading_data && @state
          status = case @state.status
                   when :running then "RUNNING"
                   when :paused  then "PAUSED"
                   else @state.status.to_s.upcase
                   end
          pnl = @state.pnl.to_f
          pnl_s = pnl >= 0 ? "+#{pnl.round(0)}" : pnl.round(0).to_s
          status_lines.unshift(@pastel.dim("Trading Status: #{status} | Session PnL: #{pnl_s}"))
        end

        TTY::Box.frame(
          width: width,
          style: { border: { fg: :bright_black } }
        ) { status_lines.join("  •  ") }
      end

      def fmt_price(v)
        return "---" if v.nil?
        format("%0.2f", v)
      end

      def trend_pill(ltp, tick = nil)
        return "---" unless ltp

        # Use previous close for trend calculation if available
        if tick && tick[:prev_close] && tick[:prev_close] > 0
          prev_close = tick[:prev_close]
          if ltp > prev_close
            @pastel.green.bold(" ▲ ")
          elsif ltp < prev_close
            @pastel.red.bold(" ▼ ")
          else
            @pastel.yellow.bold(" ● ")
          end
        else
          # Fallback: use last digit for visual indication
          sym = ltp.to_i.even? ? "▲" : "▼"
          color = sym == "▲" ? :green : :red
          @pastel.public_send(color).bold(" #{sym} ")
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
