# frozen_string_literal: true

require "tty-table"
require "tty-box"
require "tty-cursor"
require "tty-screen"
require "pastel"
require_relative "../virtual_data_manager"

module DhanScalper
  module UI
    class DataViewer
      REFRESH = 5

      def initialize
        @pastel = Pastel.new
        @vdm = VirtualDataManager.new
        @cursor = TTY::Cursor
        @alive = true
      end

      def run
        trap_signals
        hide_cursor
        loop do
          break unless @alive

          render_frame
          sleep REFRESH
        end
      rescue Interrupt
        puts "\n#{@pastel.yellow("Data viewer stopped.")}"
      ensure
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

      def render_frame
        width = TTY::Screen.width
        clear_screen
        print header_box(width)
        print balance_box(width)
        print positions_box(width)
        print recent_orders_box(width)
        print footer_hint(width)
      end

      # -------------------- widgets --------------------

      def header_box(width)
        TTY::Box.frame(
          width: width,
          title: { top_left: " DHAN SCALPER - VIRTUAL DATA DASHBOARD " },
          style: { border: { fg: :bright_blue } }
        ) do
          "Press Ctrl+C to exit | Data refreshes every #{REFRESH} seconds"
        end
      end

      def balance_box(width)
        balance = @vdm.get_balance

        TTY::Box.frame(
          width: width,
          title: { top_left: " 💰 ACCOUNT BALANCE " },
          style: { border: { fg: :bright_green } }
        ) do
          [
            "Available: #{@pastel.green("₹#{balance[:available].to_f.round(2)}")}",
            "Used: #{@pastel.red("₹#{balance[:used].to_f.round(2)}")}",
            "Total: #{@pastel.blue("₹#{balance[:total].to_f.round(2)}")}"
          ].join("\n")
        end
      end

      def positions_box(width)
        positions = @vdm.get_positions

        if positions.empty?
          return TTY::Box.frame(
            width: width,
            title: { top_left: " 📊 POSITIONS " },
            style: { border: { fg: :bright_black } }
          ) do
            @pastel.yellow("No open positions")
          end
        end

        headers = ["Symbol", "Side", "Qty", "Entry", "Current", "P&L"]
        rows = positions.map do |pos|
          pnl_value = pos[:pnl].to_f
          pnl_color = pnl_value >= 0 ? :green : :red
          [
            pos[:symbol] || pos[:security_id],
            @pastel.send(pos[:side] == "BUY" ? :green : :red, pos[:side]),
            pos[:quantity],
            "₹#{pos[:entry_price].to_f.round(2)}",
            "₹#{pos[:current_price].to_f.round(2)}",
            @pastel.send(pnl_color, "₹#{pnl_value.round(2)}")
          ]
        end

        table = TTY::Table.new(headers, rows)
        content = table.render(:ascii, resize: true)

        TTY::Box.frame(
          width: width,
          title: { top_left: " 📊 POSITIONS " },
          style: { border: { fg: :bright_black } }
        ) { content }
      end

      def recent_orders_box(width)
        orders = @vdm.get_orders(limit: 5)

        if orders.empty?
          return TTY::Box.frame(
            width: width,
            title: { top_left: " 📋 RECENT ORDERS " },
            style: { border: { fg: :bright_black } }
          ) do
            @pastel.yellow("No orders found")
          end
        end

        headers = %w[ID Side Qty Price Time]
        rows = orders.map do |order|
          [
            "#{order[:id][0..8]}...",
            @pastel.send(order[:side] == "BUY" ? :green : :red, order[:side]),
            order[:quantity],
            "₹#{order[:avg_price].to_f.round(2)}",
            Time.parse(order[:timestamp]).strftime("%H:%M:%S")
          ]
        end

        table = TTY::Table.new(headers, rows)
        content = table.render(:ascii, resize: true)

        TTY::Box.frame(
          width: width,
          title: { top_left: " 📋 RECENT ORDERS " },
          style: { border: { fg: :bright_black } }
        ) { content }
      end

      def footer_hint(_width)
        @pastel.dim("Press Ctrl+C to exit | Data refreshes every #{REFRESH} seconds")
      end
    end
  end
end
