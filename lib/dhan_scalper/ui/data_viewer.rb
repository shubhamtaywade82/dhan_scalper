# frozen_string_literal: true

require "tty-table"
require "tty-box"
require "pastel"
require_relative "../virtual_data_manager"

module DhanScalper
  module UI
    class DataViewer
      def initialize
        @pastel = Pastel.new
        @vdm = VirtualDataManager.new
      end

      def display_dashboard
        system "clear" or system "cls"

        puts @pastel.blue.bold("=" * 80)
        puts @pastel.blue.bold("                    DHAN SCALPER - VIRTUAL DATA DASHBOARD")
        puts @pastel.blue.bold("=" * 80)
        puts

        display_balance
        puts
        display_positions
        puts
        display_recent_orders
        puts
        puts @pastel.yellow("Press Ctrl+C to exit | Data refreshes every 5 seconds")
      end

      def display_balance
        balance = @vdm.get_balance

        balance_box = TTY::Box.frame(
          width: 80,
          height: 6,
          title: { top_left: " 💰 ACCOUNT BALANCE " },
          border: :thick
        ) do
          [
            "Available: #{@pastel.green("₹#{balance[:available].round(2)}")}",
            "Used: #{@pastel.red("₹#{balance[:used].round(2)}")}",
            "Total: #{@pastel.blue("₹#{balance[:total].round(2)}")}"
          ].join("\n")
        end

        puts balance_box
      end

      def display_positions
        positions = @vdm.get_positions

        if positions.empty?
          positions_box = TTY::Box.frame(
            width: 80,
            height: 4,
            title: { top_left: " 📊 POSITIONS " },
            border: :thick
          ) do
            @pastel.yellow("No open positions")
          end
          puts positions_box
          return
        end

        headers = ["Symbol", "Side", "Qty", "Entry", "Current", "P&L"]
        rows = positions.map do |pos|
          pnl_color = pos[:pnl] >= 0 ? :green : :red
          [
            pos[:symbol] || pos[:security_id],
            @pastel.send(pos[:side] == "BUY" ? :green : :red, pos[:side]),
            pos[:quantity],
            "₹#{pos[:entry_price].round(2)}",
            "₹#{pos[:current_price].round(2)}",
            @pastel.send(pnl_color, "₹#{pos[:pnl]&.round(2)}")
          ]
        end

        table = TTY::Table.new(headers, rows)
        positions_box = TTY::Box.frame(
          width: 80,
          height: positions.length + 3,
          title: { top_left: " 📊 POSITIONS " },
          border: :thick
        ) do
          table.render(:ascii)
        end

        puts positions_box
      end

      def display_recent_orders
        orders = @vdm.get_orders(limit: 5)

        if orders.empty?
          orders_box = TTY::Box.frame(
            width: 80,
            height: 4,
            title: { top_left: " 📋 RECENT ORDERS " },
            border: :thick
          ) do
            @pastel.yellow("No orders found")
          end
          puts orders_box
          return
        end

        headers = %w[ID Side Qty Price Time]
        rows = orders.map do |order|
          [
            "#{order[:id][0..8]}...",
            @pastel.send(order[:side] == "BUY" ? :green : :red, order[:side]),
            order[:quantity],
            "₹#{order[:avg_price].round(2)}",
            Time.parse(order[:timestamp]).strftime("%H:%M:%S")
          ]
        end

        table = TTY::Table.new(headers, rows)
        orders_box = TTY::Box.frame(
          width: 80,
          height: orders.length + 3,
          title: { top_left: " 📋 RECENT ORDERS " },
          border: :thick
        ) do
          table.render(:ascii)
        end

        puts orders_box
      end

      def run
        loop do
          display_dashboard
          sleep 5
        end
      rescue Interrupt
        puts "\n#{@pastel.yellow("Data viewer stopped.")}"
      end
    end
  end
end
