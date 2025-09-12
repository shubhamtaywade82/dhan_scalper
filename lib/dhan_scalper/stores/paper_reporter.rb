# frozen_string_literal: true

require "csv"
require "json"
require "fileutils"

module DhanScalper
  module Stores
    # Paper trading reporter for session reports and data persistence
    class PaperReporter
      attr_reader :data_dir, :logger

      def initialize(data_dir: "data", logger: nil)
        @data_dir = data_dir
        @logger = logger || Logger.new($stdout)
        ensure_data_directory
      end

      # Generate session report
      def generate_session_report(session_data)
        session_id = session_data[:session_id] || generate_session_id
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")

        # Generate JSON report
        json_file = File.join(@data_dir, "reports", "session_#{session_id}_#{timestamp}.json")
        save_json_report(json_file, session_data)

        # Generate CSV report
        csv_file = File.join(@data_dir, "reports", "session_#{session_id}_#{timestamp}.csv")
        save_csv_report(csv_file, session_data)

        # Store in Redis if available
        store_report_in_redis(session_id, csv_file, session_data)

        {
          session_id: session_id,
          json_file: json_file,
          csv_file: csv_file,
          timestamp: timestamp
        }
      end

      # Save positions to CSV
      def save_positions(positions, position_type = "open")
        filename = "#{position_type}_positions.csv"
        file_path = File.join(@data_dir, filename)

        return if positions.empty?

        CSV.open(file_path, "w") do |csv|
          # Headers
          csv << %w[
            symbol security_id side entry_price current_price quantity
            pnl pnl_percentage option_type strike expiry timestamp
            exit_price exit_reason exit_timestamp
          ]

          # Data rows
          positions.each do |position|
            csv << [
              position[:symbol],
              position[:security_id],
              position[:side],
              position[:entry_price],
              position[:current_price],
              position[:quantity],
              position[:pnl],
              position[:pnl_percentage],
              position[:option_type],
              position[:strike],
              position[:expiry],
              position[:timestamp],
              position[:exit_price],
              position[:exit_reason],
              position[:exit_timestamp]
            ]
          end
        end

        @logger.info "[PAPER_REPORTER] Saved #{positions.size} #{position_type} positions to #{file_path}"
        file_path
      end

      # Save orders to CSV
      def save_orders(orders)
        filename = "orders.csv"
        file_path = File.join(@data_dir, filename)

        return if orders.empty?

        CSV.open(file_path, "w") do |csv|
          # Headers
          csv << %w[
            id symbol security_id side quantity price order_type
            status timestamp filled_price filled_quantity
          ]

          # Data rows
          orders.each do |order|
            csv << [
              order[:id],
              order[:symbol],
              order[:security_id],
              order[:side],
              order[:quantity],
              order[:price],
              order[:order_type],
              order[:status],
              order[:timestamp],
              order[:filled_price],
              order[:filled_quantity]
            ]
          end
        end

        @logger.info "[PAPER_REPORTER] Saved #{orders.size} orders to #{file_path}"
        file_path
      end

      # Save balance to JSON
      def save_balance(balance_data)
        filename = "balance.json"
        file_path = File.join(@data_dir, filename)

        File.write(file_path, JSON.pretty_generate(balance_data))
        @logger.info "[PAPER_REPORTER] Saved balance to #{file_path}"
        file_path
      end

      # Load positions from CSV
      def load_positions(position_type = "open")
        filename = "#{position_type}_positions.csv"
        file_path = File.join(@data_dir, filename)

        return [] unless File.exist?(file_path)

        positions = []
        CSV.foreach(file_path, headers: true) do |row|
          positions << {
            symbol: row["symbol"],
            security_id: row["security_id"],
            side: row["side"],
            entry_price: row["entry_price"].to_f,
            current_price: row["current_price"].to_f,
            quantity: row["quantity"].to_i,
            pnl: row["pnl"].to_f,
            pnl_percentage: row["pnl_percentage"].to_f,
            option_type: row["option_type"],
            strike: row["strike"]&.to_f,
            expiry: row["expiry"],
            timestamp: row["timestamp"],
            exit_price: row["exit_price"]&.to_f,
            exit_reason: row["exit_reason"],
            exit_timestamp: row["exit_timestamp"]
          }
        end

        @logger.info "[PAPER_REPORTER] Loaded #{positions.size} #{position_type} positions from #{file_path}"
        positions
      end

      # Load orders from CSV
      def load_orders
        filename = "orders.csv"
        file_path = File.join(@data_dir, filename)

        return [] unless File.exist?(file_path)

        orders = []
        CSV.foreach(file_path, headers: true) do |row|
          orders << {
            id: row["id"],
            symbol: row["symbol"],
            security_id: row["security_id"],
            side: row["side"],
            quantity: row["quantity"].to_i,
            price: row["price"].to_f,
            order_type: row["order_type"],
            status: row["status"],
            timestamp: row["timestamp"],
            filled_price: row["filled_price"]&.to_f,
            filled_quantity: row["filled_quantity"]&.to_i
          }
        end

        @logger.info "[PAPER_REPORTER] Loaded #{orders.size} orders from #{file_path}"
        orders
      end

      # Load balance from JSON
      def load_balance
        filename = "balance.json"
        file_path = File.join(@data_dir, filename)

        return nil unless File.exist?(file_path)

        data = JSON.parse(File.read(file_path), symbolize_names: true)
        @logger.info "[PAPER_REPORTER] Loaded balance from #{file_path}"
        data
      end

      # List available sessions
      def list_sessions
        reports_dir = File.join(@data_dir, "reports")
        return [] unless Dir.exist?(reports_dir)

        sessions = []
        Dir.glob(File.join(reports_dir, "session_*.json")).each do |file|
          filename = File.basename(file, ".json")
          session_id = filename.split("_")[1..2].join("_")
          timestamp = filename.split("_")[3..4].join("_")

          sessions << {
            session_id: session_id,
            timestamp: timestamp,
            json_file: file,
            csv_file: file.gsub(".json", ".csv")
          }
        end

        sessions.sort_by { |s| s[:timestamp] }.reverse
      end

      # Get latest session
      def get_latest_session
        sessions = list_sessions
        sessions.first
      end

      # Clean up old data
      def cleanup_old_data(days_to_keep = 7)
        cutoff_time = Time.now - (days_to_keep * 24 * 60 * 60)

        # Clean up old reports
        reports_dir = File.join(@data_dir, "reports")
        if Dir.exist?(reports_dir)
          Dir.glob(File.join(reports_dir, "session_*.json")).each do |file|
            next unless File.mtime(file) < cutoff_time

            FileUtils.rm_f(file)
            FileUtils.rm_f(file.gsub(".json", ".csv"))
            @logger.info "[PAPER_REPORTER] Cleaned up old report: #{file}"
          end
        end

        @logger.info "[PAPER_REPORTER] Cleanup completed (kept last #{days_to_keep} days)"
      end

      private

      def ensure_data_directory
        FileUtils.mkdir_p(@data_dir)
        FileUtils.mkdir_p(File.join(@data_dir, "reports"))
      end

      def generate_session_id
        "PAPER_#{Time.now.strftime("%Y%m%d_%H%M%S")}"
      end

      def save_json_report(file_path, session_data)
        FileUtils.mkdir_p(File.dirname(file_path))
        File.write(file_path, JSON.pretty_generate(session_data))
        @logger.info "[PAPER_REPORTER] Saved JSON report to #{file_path}"
      end

      def save_csv_report(file_path, session_data)
        FileUtils.mkdir_p(File.dirname(file_path))

        CSV.open(file_path, "w") do |csv|
          # Session summary
          csv << ["Session ID", session_data[:session_id]]
          csv << ["Mode", session_data[:mode]]
          csv << ["Duration", session_data[:duration]]
          csv << ["Start Time", session_data[:start_time]]
          csv << ["End Time", session_data[:end_time]]
          csv << ["Symbols", session_data[:symbols]&.join(", ")]
          csv << []

          # Trading performance
          csv << ["Trading Performance"]
          csv << ["Total Trades", session_data[:total_trades]]
          csv << ["Successful Trades", session_data[:successful_trades]]
          csv << ["Failed Trades", session_data[:failed_trades]]
          csv << ["Win Rate", "#{session_data[:win_rate]}%"]
          csv << []

          # Financial summary
          csv << ["Financial Summary"]
          csv << ["Starting Balance", DhanScalper::Support::Money.format(session_data[:starting_balance] || 0)]
          csv << ["Ending Balance", DhanScalper::Support::Money.format(session_data[:ending_balance] || 0)]
          csv << ["Total P&L", DhanScalper::Support::Money.format(session_data[:total_pnl] || 0)]
          csv << ["Max Profit", DhanScalper::Support::Money.format(session_data[:max_profit] || 0)]
          csv << ["Max Drawdown", DhanScalper::Support::Money.format(session_data[:max_drawdown] || 0)]
          csv << ["Avg Trade P&L", DhanScalper::Support::Money.format(session_data[:avg_trade_pnl] || 0)]
          csv << []

          # Positions
          if session_data[:positions] && session_data[:positions].any?
            csv << ["Positions"]
            csv << %w[Symbol Security_ID Side Entry_Price Current_Price Quantity PnL PnL_Percentage]
            session_data[:positions].each do |position|
              csv << [
                position[:symbol],
                position[:security_id],
                position[:side],
                position[:entry_price],
                position[:current_price],
                position[:quantity],
                position[:pnl],
                "#{position[:pnl_percentage]}%"
              ]
            end
          end
        end

        @logger.info "[PAPER_REPORTER] Saved CSV report to #{file_path}"
      end

      def store_report_in_redis(session_id, _csv_file, _session_data)
        # This would integrate with RedisStore if available
        # For now, just log the action
        @logger.info "[PAPER_REPORTER] Would store report in Redis: #{session_id}"
      end
    end
  end
end
