# frozen_string_literal: true

require "tty/table"
require "tty/box"
require "tty/reader"
require "tty/screen"
require "pastel"

module DhanScalper
  module UI
    class Dashboard
      REFRESH = 0.5

      def initialize(state, balance_provider: nil)
        @st   = state
        @balance_provider = balance_provider
        @pd   = Pastel.new
        @rd   = TTY::Reader.new
        @show_subs = true
        @alive = true
      end

      def run
        trap_signals
        hide_cursor
        input_thread = Thread.new { read_keys }
        loop do
          break unless @alive

          render_frame
          sleep REFRESH
        end
      ensure
        input_thread&.kill
        show_cursor
      end

      private

      def trap_signals
        Signal.trap("INT") { @alive = false }
        Signal.trap("TERM") { @alive = false }
      end

      def hide_cursor
        print "\e[?25l"
      end

      def show_cursor
        print "\e[?25h"
      end

      def clear_screen
        print "\e[2J\e[H"
      end

      def read_keys
        @rd.on(:keypress) do |e|
          case e.value
          when "q" then @alive = false
          when "p" then @st.set_status(:paused)
          when "r" then @st.set_status(:running)
          when "s" then @show_subs = !@show_subs
          end
        end
        @rd.read_keypress while @alive
      end

      def render_frame
        width = TTY::Screen.width
        clear_screen
        puts header_box(width)
        puts balance_box(width) if @balance_provider
        puts positions_box(width)
        puts closed_box(width)
        puts subs_box(width) if @show_subs
        puts footer_hint
      end

      # -------------------- widgets --------------------

      def header_box(width)
        status = case @st.status
                 when :running then @pd.green("RUNNING")
                 when :paused  then @pd.yellow("PAUSED")
                 else @pd.red(@st.status.to_s.upcase)
                 end

        pnl    = @st.pnl
        pnl_s  = pnl >= 0 ? @pd.green("+#{pnl.round(0)}") : @pd.red(pnl.round(0).to_s)
        tgt    = @st.session_target
        mdd    = @st.max_day_loss
        syms   = @st.symbols.join(", ")

        TTY::Box.frame(
          width: width,
          title: { top_left: " DhanScalper " },
          style: { border: { fg: :bright_blue } }
        ) do
          <<~TEXT
            Status: #{status}   Session PnL: #{pnl_s}   Target: #{tgt}   Max DD: -#{mdd}
            Symbols: #{syms}
            Controls: #{kbd("q")}uit  #{kbd("p")}ause  #{kbd("r")}esume  #{kbd("s")}ubscriptions toggle
          TEXT
        end
      end

      def balance_box(width)
        return "" unless @balance_provider

        available = @balance_provider.available_balance
        used = @balance_provider.used_balance
        total = @balance_provider.total_balance

        TTY::Box.frame(
          width: width,
          title: { top_left: " 💰 ACCOUNT BALANCE " },
          style: { border: { fg: :bright_green } }
        ) do
          <<~TEXT
            Available: #{@pd.green("₹#{available.round(2)}")}   Used: #{@pd.red("₹#{used.round(2)}")}   Total: #{@pd.blue("₹#{total.round(2)}")}
          TEXT
        end
      end

      def positions_box(width)
        rows = @st.open.map do |p|
          net = p[:net].to_f
          [
            p[:symbol],
            p[:side],
            p[:sid],
            p[:qty_lots],
            fmt_price(p[:entry]),
            fmt_price(p[:ltp]),
            net >= 0 ? @pd.green(net.round(0)) : @pd.red(net.round(0)),
            p[:best].round(0)
          ]
        end

        table = TTY::Table.new(
          header: ["Symbol", "Side", "SID", "Lots", "Entry", "LTP", "Net₹", "Best₹"],
          rows: rows
        )
        content = rows.empty? ? @pd.dim("No open positions") : table.render(:unicode, resize: true)
        boxed(" Open Positions ", content, width)
      end

      def closed_box(width)
        rows = @st.closed.last(10).reverse.map do |p|
          net = p[:net].to_f
          [
            p[:symbol], p[:side], p[:reason],
            fmt_price(p[:entry]), fmt_price(p[:exit_price]),
            net >= 0 ? @pd.green(net.round(0)) : @pd.red(net.round(0))
          ]
        end
        table = TTY::Table.new(
          header: ["Symbol", "Side", "Reason", "Entry", "Exit", "Net₹"],
          rows: rows
        )
        content = rows.empty? ? @pd.dim("No recent closed positions") : table.render(:unicode, resize: true)
        boxed(" Closed Positions (10) ", content, width)
      end

      def subs_box(width)
        idx_rows = @st.subs_idx.map do |r|
          [r[:symbol], "#{r[:segment]}:#{r[:security_id]}", fmt_price(r[:ltp]), ago(r[:ts])]
        end
        opt_rows = @st.subs_opt.map do |r|
          [r[:symbol], "#{r[:segment]}:#{r[:security_id]}", fmt_price(r[:ltp]), ago(r[:ts])]
        end

        idx_tbl = TTY::Table.new(header: %w[Index Key LTP Age], rows: idx_rows)
        opt_tbl = TTY::Table.new(header: %w[Option Key LTP Age], rows: opt_rows)

        content = +""
        content << boxed(" Index Subscriptions ",
                         idx_rows.empty? ? @pd.dim("None") : idx_tbl.render(:unicode, resize: true), width)
        content << "\n"
        content << boxed(" Option Subscriptions ",
                         opt_rows.empty? ? @pd.dim("None") : opt_tbl.render(:unicode, resize: true), width)
        content
      end

      # -------------------- helpers --------------------
      def boxed(title, content, width)
        TTY::Box.frame(width: width, title: { top_left: title }, style: { border: { fg: :bright_black } }) { content }
      end

      def kbd(s) = @pd.bright_white("[#{s}]")

      def fmt_price(v)
        return "-" if v.nil?

        v.to_f.round(2)
      end

      def ago(ts)
        return "-" unless ts

        dt = Time.now.to_i - ts.to_i
        dt < 2 ? "1s" : "#{dt}s"
      end

      def footer_hint
        @pd.dim("Press 'q' to quit, 'p' to pause, 'r' to resume, 's' to toggle subscriptions")
      end
    end
  end
end
