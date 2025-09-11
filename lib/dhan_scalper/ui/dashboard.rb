# frozen_string_literal: true

require "tty/table"
require "tty/box"
require "tty/reader"
require "tty/screen"
require "tty/cursor"
require "pastel"

module DhanScalper
  module UI
    class Dashboard
      REFRESH = 0.5

      def initialize(state, balance_provider: nil)
        @st = state
        @balance_provider = balance_provider
        @pd   = Pastel.new
        @rd   = TTY::Reader.new
        @cur  = TTY::Cursor
        @show_subs = true
        @alive = true
        @width, @height = TTY::Screen.size
        $stdout.sync = true # unbuffered so cursor ops are immediate
      end

      def run
        trap_signals
        hide_cursor
        render_loop
      ensure
        show_cursor
      end

      private

      # ---------- terminal control ----------
      def enter_alternate_screen
        # switch to alt screen (no scrollback pollution)
        print "\e[?1049h"
      end

      def exit_alternate_screen
        print "\e[?1049l"
      end

      def hide_cursor
        print "\e[?25l"
      end

      def show_cursor
        print "\e[?25h"
      end

      def clear_fullscreen!
        # Simple clear screen
        system("clear") || system("cls")
      end

      def trap_signals
        Signal.trap("INT") {  @alive = false }
        Signal.trap("TERM") { @alive = false }
        Signal.trap("WINCH") do
          @width, @height = TTY::Screen.size
        end
        # keyboard
        Thread.new do
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
      end

      # ---------- main render loop ----------
      def render_loop
        while @alive
          # Paint the whole screen in place (no puts!)
          clear_fullscreen!
          print header_box
          print balance_box
          print positions_box
          print closed_box
          print subs_box if @show_subs
          print footer_hint
          $stdout.flush
          sleep REFRESH
        end
      end

      # ---------- widgets ----------
      def header_box
        status = case @st.status
                 when :running then "RUNNING"
                 when :paused  then "PAUSED"
                 else @st.status.to_s.upcase
                 end
        pnl    = @st.pnl.to_f
        pnl_s  = pnl >= 0 ? "+#{pnl.round(0)}" : pnl.round(0).to_s
        tgt    = @st.session_target
        mdd    = @st.max_day_loss
        syms   = @st.symbols.join(", ")

        TTY::Box.frame(
          width: @width,
          title: { top_left: " DhanScalper " },
          style: { border: { fg: :bright_blue } }
        ) do
          <<~TEXT
            Status: #{status}   Session PnL: #{pnl_s}   Target: #{tgt}   Max DD: -#{mdd}
            Symbols: #{syms}
            Controls: [q]uit  [p]ause  [r]esume  [s]ubscriptions toggle
          TEXT
        end
      end

      def balance_box
        return "" unless @balance_provider

        available = @balance_provider.available_balance.to_f.round(0)
        used = @balance_provider.used_balance.to_f.round(0)
        total = @balance_provider.total_balance.to_f.round(0)

        content = <<~TEXT
          Available: ₹#{available}   Used: ₹#{used}   Total: ₹#{total}
        TEXT

        boxed(" Balance ", content)
      end

      def positions_box
        rows = @st.open.map do |p|
          net = p[:net].to_f
          [
            p[:symbol],
            p[:side],
            p[:sid],
            p[:qty_lots],
            fmt(p[:entry]),
            fmt(p[:ltp]),
            net.round(0).to_s,
            p[:best].to_f.round(0)
          ]
        end
        table = TTY::Table.new(
          header: ["Symbol", "Side", "SID", "Lots", "Entry", "LTP", "Net₹", "Best₹"],
          rows: rows
        )
        content = rows.empty? ? "No open positions" : table.render(:ascii, resize: true)
        boxed(" Open Positions ", content)
      end

      def closed_box
        rows = @st.closed.last(10).reverse.map do |p|
          net = p[:net].to_f
          [
            p[:symbol], p[:side], p[:reason],
            fmt(p[:entry]), fmt(p[:exit_price]),
            net.round(0).to_s
          ]
        end
        table = TTY::Table.new(
          header: ["Symbol", "Side", "Reason", "Entry", "Exit", "Net₹"],
          rows: rows
        )
        content = rows.empty? ? "No recent closed positions" : table.render(:ascii, resize: true)
        boxed(" Closed Positions (10) ", content)
      end

      def subs_box
        idx_rows = @st.subs_idx.map { |r| [r[:symbol], "#{r[:segment]}:#{r[:security_id]}", fmt(r[:ltp]), age(r[:ts])] }
        opt_rows = @st.subs_opt.map { |r| [r[:symbol], "#{r[:segment]}:#{r[:security_id]}", fmt(r[:ltp]), age(r[:ts])] }
        idx_tbl = TTY::Table.new(header: %w[Index Key LTP Age], rows: idx_rows)
        opt_tbl = TTY::Table.new(header: %w[Option Key LTP Age], rows: opt_rows)

        out  = boxed(" Index Subscriptions ", idx_rows.empty? ? "None" : idx_tbl.render(:ascii, resize: true))
        out << boxed(" Option Subscriptions ", opt_rows.empty? ? "None" : opt_tbl.render(:ascii, resize: true))
        out
      end

      def footer_hint
        # Fit a small footer inside width
        TTY::Box.frame(
          width: @width,
          style: { border: { fg: :bright_black } }
        ) { "Updated: #{Time.now.strftime("%H:%M:%S")}  •  Resize supported" }
      end

      # ---------- helpers ----------
      def boxed(title, content)
        TTY::Box.frame(width: @width, title: { top_left: title }, style: { border: { fg: :bright_black } }) { content }
      end

      def fmt(v) = v.nil? ? "-" : v.to_f.round(2)

      def age(ts)
        return "-" unless ts

        d = (Time.now.to_i - ts.to_i).abs
        d < 2 ? "1s" : "#{d}s"
      end
    end
  end
end
