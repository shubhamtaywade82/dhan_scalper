# frozen_string_literal: true

require "csv"
require "json"
require "fileutils"
require "time"
require_relative "../support/money"

module DhanScalper
  module Services
    class SessionReporter
      def initialize
        @data_dir = "data"
        @reports_dir = File.join(@data_dir, "reports")

        # Ensure the reports directory exists
        begin
          FileUtils.mkdir_p(@reports_dir)
          puts "[REPORTS] Reports directory created: #{@reports_dir}" if ENV["DHAN_LOG_LEVEL"] == "DEBUG"
        rescue StandardError => e
          puts "[REPORTS] Warning: Failed to create reports directory: #{e.message}"
          # Fallback to current directory if data directory creation fails
          @reports_dir = "reports"
          FileUtils.mkdir_p(@reports_dir)
        end
      end

      # Generate a comprehensive session report
      def generate_session_report(session_data)
        session_id = session_data[:session_id] || generate_session_id
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")

        report_data = {
          session_id: session_id,
          timestamp: timestamp,
          start_time: session_data[:start_time],
          end_time: session_data[:end_time],
          duration_minutes: session_data[:duration_minutes],
          mode: session_data[:mode] || "paper",
          symbols_traded: session_data[:symbols_traded] || [],
          total_trades: session_data[:total_trades] || 0,
          successful_trades: session_data[:successful_trades] || 0,
          failed_trades: session_data[:failed_trades] || 0,
          total_pnl: session_data[:total_pnl] || 0.0,
          starting_balance: session_data[:starting_balance] || 0.0,
          ending_balance: session_data[:ending_balance] || 0.0,
          used_balance: session_data[:used_balance] || 0.0,
          total_balance: session_data[:total_balance] || 0.0,
          max_drawdown: session_data[:max_drawdown] || 0.0,
          max_profit: session_data[:max_profit] || 0.0,
          win_rate: session_data[:win_rate] || 0.0,
          average_trade_pnl: session_data[:average_trade_pnl] || 0.0,
          positions: session_data[:positions] || [],
          trades: session_data[:trades] || [],
          risk_metrics: session_data[:risk_metrics] || {},
          performance_summary: session_data[:performance_summary] || {},
        }

        # Ensure reports directory exists before writing
        ensure_reports_directory

        # Save JSON report
        json_file = File.join(@reports_dir, "session_#{session_id}_#{timestamp}.json")
        begin
          File.write(json_file, JSON.pretty_generate(report_data))
        rescue StandardError => e
          puts "[REPORTS] Error writing JSON report: #{e.message}"
          # Fallback to current directory
          json_file = "session_#{session_id}_#{timestamp}.json"
          File.write(json_file, JSON.pretty_generate(report_data))
        end

        # Save CSV report
        csv_file = File.join(@reports_dir, "session_#{session_id}_#{timestamp}.csv")
        begin
          save_csv_report(csv_file, report_data)
        rescue StandardError => e
          puts "[REPORTS] Error writing CSV report: #{e.message}"
          # Fallback to current directory
          csv_file = "session_#{session_id}_#{timestamp}.csv"
          save_csv_report(csv_file, report_data)
        end

        # Generate console summary
        generate_console_summary(report_data)

        {
          session_id: session_id,
          json_file: json_file,
          csv_file: csv_file,
          report_data: report_data,
        }
      end

      # Generate report for a specific session
      def generate_report_for_session(session_id)
        json_files = Dir.glob(File.join(@reports_dir, "session_#{session_id}_*.json"))

        if json_files.empty?
          puts "No report found for session ID: #{session_id}"
          return nil
        end

        # Get the latest file for this session
        latest_file = json_files.max_by { |f| File.mtime(f) }
        report_data = JSON.parse(File.read(latest_file), symbolize_names: true)

        generate_console_summary(report_data)
        report_data
      end

      # Generate report for the latest session
      def generate_latest_session_report
        json_files = Dir.glob(File.join(@reports_dir, "session_*.json"))

        if json_files.empty?
          puts "No session reports found"
          return nil
        end

        # Get the latest file
        latest_file = json_files.max_by { |f| File.mtime(f) }
        report_data = JSON.parse(File.read(latest_file), symbolize_names: true)

        generate_console_summary(report_data)
        report_data
      end

      # List available sessions
      def list_available_sessions
        json_files = Dir.glob(File.join(@reports_dir, "session_*.json"))

        json_files.map do |file|
          data = JSON.parse(File.read(file), symbolize_names: true)
          {
            session_id: data[:session_id],
            created: File.mtime(file).strftime("%Y-%m-%d %H:%M:%S"),
            size: File.size(file),
          }
        end.sort_by { |s| s[:created] }.reverse
      end

      private

      def ensure_reports_directory
        return if Dir.exist?(@reports_dir)

        begin
          FileUtils.mkdir_p(@reports_dir)
          puts "[REPORTS] Created reports directory: #{@reports_dir}" if ENV["DHAN_LOG_LEVEL"] == "DEBUG"
        rescue StandardError => e
          puts "[REPORTS] Warning: Failed to create reports directory #{@reports_dir}: #{e.message}"
          # Fallback to current directory
          @reports_dir = "reports"
          FileUtils.mkdir_p(@reports_dir)
          puts "[REPORTS] Using fallback directory: #{@reports_dir}"
        end
      end

      def generate_session_id
        "PAPER_#{Time.now.strftime("%Y%m%d_%H%M%S")}"
      end

      def save_csv_report(csv_file, report_data)
        CSV.open(csv_file, "w") do |csv|
          # Header
          csv << ["Session Report", report_data[:session_id]]
          csv << ["Generated", Time.now.strftime("%Y-%m-%d %H:%M:%S")]
          csv << []

          # Session Summary
          csv << ["SESSION SUMMARY"]
          csv << ["Session ID", report_data[:session_id]]
          csv << ["Mode", report_data[:mode]]
          csv << ["Start Time", report_data[:start_time]]
          csv << ["End Time", report_data[:end_time]]
          csv << ["Duration (minutes)", report_data[:duration_minutes]]
          csv << ["Symbols Traded", report_data[:symbols_traded].join(", ")]
          csv << []

          # Trading Summary
          csv << ["TRADING SUMMARY"]
          csv << ["Total Trades", report_data[:total_trades]]
          csv << ["Successful Trades", report_data[:successful_trades]]
          csv << ["Failed Trades", report_data[:failed_trades]]
          csv << ["Win Rate (%)", "#{report_data[:win_rate].round(2)}%"]
          csv << []

          # Financial Summary
          csv << ["FINANCIAL SUMMARY"]
          csv << ["Starting Balance", DhanScalper::Support::Money.format(report_data[:starting_balance] || 0)]
          csv << ["Available Balance", DhanScalper::Support::Money.format(report_data[:ending_balance] || 0)]
          csv << ["Used Balance", DhanScalper::Support::Money.format(report_data[:used_balance] || 0)]
          csv << ["Total Balance", DhanScalper::Support::Money.format(report_data[:total_balance] || 0)]
          csv << ["Total P&L", DhanScalper::Support::Money.format(report_data[:total_pnl] || 0)]
          csv << ["Max Profit", DhanScalper::Support::Money.format(report_data[:max_profit] || 0)]
          csv << ["Max Drawdown", DhanScalper::Support::Money.format(report_data[:max_drawdown] || 0)]
          csv << ["Average Trade P&L", DhanScalper::Support::Money.format(report_data[:average_trade_pnl] || 0)]
          csv << []

          # Positions
          if report_data[:positions].any?
            csv << ["POSITIONS"]
            csv << ["Symbol", "Option Type", "Strike", "Quantity", "Entry Price", "Current Price", "P&L", "Created At"]
            report_data[:positions].each do |pos|
              csv << [
                pos[:symbol],
                pos[:option_type],
                pos[:strike],
                pos[:quantity],
                pos[:entry_price],
                pos[:current_price],
                pos[:pnl],
                pos[:created_at],
              ]
            end
            csv << []
          end

          # Trades
          if report_data[:trades].any?
            csv << ["TRADES"]
            csv << ["Time", "Symbol", "Side", "Quantity", "Price", "Order ID", "Status"]
            report_data[:trades].each do |trade|
              csv << [
                trade[:timestamp],
                trade[:symbol],
                trade[:side],
                trade[:quantity],
                trade[:price],
                trade[:order_id],
                trade[:status],
              ]
            end
          end
        end
      end

      def generate_console_summary(report_data)
        puts "\n#{"=" * 80}"
        puts "📊 SESSION REPORT - #{report_data[:session_id]}"
        puts "=" * 80

        # Session Info
        puts "\n🕐 SESSION INFO:"
        puts "  Mode: #{report_data[:mode].upcase}"
        puts "  Duration: #{report_data[:duration_minutes]&.round(1)} minutes"
        puts "  Start: #{report_data[:start_time]}"
        puts "  End: #{report_data[:end_time]}"
        puts "  Symbols: #{report_data[:symbols_traded].join(", ")}"

        # Trading Performance
        puts "\n📈 TRADING PERFORMANCE:"
        puts "  Total Trades: #{report_data[:total_trades]}"
        puts "  Successful: #{report_data[:successful_trades]}"
        puts "  Failed: #{report_data[:failed_trades]}"
        puts "  Win Rate: #{report_data[:win_rate]&.round(2)}%"

        # Financial Summary
        puts "\n💰 FINANCIAL SUMMARY:"
        puts "  Starting Balance: #{DhanScalper::Support::Money.format(report_data[:starting_balance] || 0)}"
        puts "  Available Balance: #{DhanScalper::Support::Money.format(report_data[:ending_balance] || 0)}"
        puts "  Used Balance: #{DhanScalper::Support::Money.format(report_data[:used_balance] || 0)}"
        puts "  Total Balance: #{DhanScalper::Support::Money.format(report_data[:total_balance] || 0)}"
        puts "  Total P&L: #{DhanScalper::Support::Money.format(report_data[:total_pnl] || 0)}"
        puts "  Max Profit: #{DhanScalper::Support::Money.format(report_data[:max_profit] || 0)}"
        puts "  Max Drawdown: #{DhanScalper::Support::Money.format(report_data[:max_drawdown] || 0)}"
        puts "  Avg Trade P&L: #{DhanScalper::Support::Money.format(report_data[:average_trade_pnl] || 0)}"

        # Performance Rating
        pnl = (report_data[:total_pnl] || 0).to_f
        if pnl.positive?
          puts "\n✅ SESSION RESULT: PROFITABLE"
        elsif pnl.negative?
          puts "\n❌ SESSION RESULT: LOSS"
        else
          puts "\n➖ SESSION RESULT: BREAKEVEN"
        end

        # Risk Metrics
        if report_data[:risk_metrics]&.any?
          puts "\n⚠️  RISK METRICS:"
          report_data[:risk_metrics].each do |key, value|
            puts "  #{key.to_s.tr("_", " ").capitalize}: #{value}"
          end
        end

        puts "=" * 80
        puts "📁 Reports saved to: #{@reports_dir}"
        puts "=" * 80
      end
    end
  end
end
