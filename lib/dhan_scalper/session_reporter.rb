# frozen_string_literal: true

require "csv"
require "json"
require "fileutils"

module DhanScalper
  class SessionReporter
    def initialize(data_dir: "data", logger: nil)
      @data_dir = data_dir
      @logger = logger || Logger.new($stdout)
      @session_id = Time.now.strftime("%Y%m%d_%H%M%S")
      @session_start = Time.now

      ensure_data_directory
    end

    def generate_session_report(position_tracker, balance_provider, config = {})
      session_stats = position_tracker.get_session_stats
      positions_summary = position_tracker.get_positions_summary

      report_data = {
        session_id: @session_id,
        session_start: @session_start,
        session_end: Time.now,
        duration_minutes: (Time.now - @session_start) / 60.0,

        # Trading statistics
        total_trades: session_stats[:total_trades],
        winning_trades: session_stats[:winning_trades],
        losing_trades: session_stats[:losing_trades],
        win_rate: calculate_win_rate(session_stats),

        # P&L statistics
        total_pnl: session_stats[:total_pnl],
        max_profit: session_stats[:max_profit],
        max_drawdown: session_stats[:max_drawdown],

        # Position statistics
        open_positions: session_stats[:open_positions],
        closed_positions: session_stats[:closed_positions],

        # Balance information
        starting_balance: config[:starting_balance] || (balance_provider.total_balance - session_stats[:total_pnl]),
        final_balance: balance_provider.total_balance,
        balance_change: session_stats[:total_pnl],
        balance_change_pct: calculate_balance_change_pct(
          config[:starting_balance] || (balance_provider.total_balance - session_stats[:total_pnl]),
          balance_provider.total_balance
        ),

        # Configuration used
        config: config,

        # Detailed position data
        positions_summary: positions_summary
      }

      # Save to CSV
      save_session_report_to_csv(report_data)

      # Save detailed positions to CSV
      save_detailed_positions_to_csv(position_tracker)

      # Print console summary
      print_console_summary(report_data)

      report_data
    end

    def generate_report_for_session(session_id)
      csv_file = File.join(@data_dir, "session_#{session_id}.csv")
      return nil unless File.exist?(csv_file)

      report_data = {}
      CSV.foreach(csv_file, headers: true) do |row|
        report_data[row["metric"]] = row["value"]
      end

      print_console_summary(report_data)
      report_data
    end

    def generate_latest_session_report
      # Find the most recent session report
      session_files = Dir.glob(File.join(@data_dir, "session_*.csv"))
      return nil if session_files.empty?

      latest_file = session_files.max_by { |f| File.mtime(f) }
      session_id = File.basename(latest_file, ".csv").gsub("session_", "")

      generate_report_for_session(session_id)
    end

    def list_available_sessions
      session_files = Dir.glob(File.join(@data_dir, "session_*.csv"))
      return [] if session_files.empty?

      session_files.map do |file|
        session_id = File.basename(file, ".csv").gsub("session_", "")
        {
          session_id: session_id,
          file: file,
          created: File.mtime(file),
          size: File.size(file)
        }
      end.sort_by { |s| s[:created] }.reverse
    end

    private

    def calculate_win_rate(stats)
      total = stats[:winning_trades] + stats[:losing_trades]
      return 0.0 if total.zero?

      (stats[:winning_trades].to_f / total) * 100
    end

    def calculate_balance_change_pct(starting_balance, final_balance)
      return 0.0 if starting_balance.zero?

      ((final_balance - starting_balance) / starting_balance) * 100
    end

    def save_session_report_to_csv(report_data)
      csv_file = File.join(@data_dir, "session_#{@session_id}.csv")

      CSV.open(csv_file, "w") do |csv|
        csv << %w[metric value]

        # Session information
        csv << ["session_id", report_data[:session_id]]
        csv << ["session_start", report_data[:session_start]]
        csv << ["session_end", report_data[:session_end]]
        csv << ["duration_minutes", report_data[:duration_minutes].round(2)]

        # Trading statistics
        csv << ["total_trades", report_data[:total_trades]]
        csv << ["winning_trades", report_data[:winning_trades]]
        csv << ["losing_trades", report_data[:losing_trades]]
        csv << ["win_rate_pct", report_data[:win_rate].round(2)]

        # P&L statistics
        csv << ["total_pnl", report_data[:total_pnl].round(2)]
        csv << ["max_profit", report_data[:max_profit].round(2)]
        csv << ["max_drawdown", report_data[:max_drawdown].round(2)]

        # Position statistics
        csv << ["open_positions", report_data[:open_positions]]
        csv << ["closed_positions", report_data[:closed_positions]]

        # Balance information
        csv << ["starting_balance", report_data[:starting_balance].round(2)]
        csv << ["final_balance", report_data[:final_balance].round(2)]
        csv << ["balance_change", report_data[:balance_change].round(2)]
        csv << ["balance_change_pct", report_data[:balance_change_pct].round(2)]
      end

      @logger.info "[REPORT] Session report saved to #{csv_file}"
    end

    def save_detailed_positions_to_csv(position_tracker)
      # Save open positions
      open_positions = position_tracker.get_open_positions
      if open_positions.any?
        csv_file = File.join(@data_dir, "session_#{@session_id}_open_positions.csv")
        save_positions_to_csv(open_positions, csv_file, "open")
      end

      # Save closed positions
      closed_positions = position_tracker.get_closed_positions
      return unless closed_positions.any?

      csv_file = File.join(@data_dir, "session_#{@session_id}_closed_positions.csv")
      save_positions_to_csv(closed_positions, csv_file, "closed")
    end

    def save_positions_to_csv(positions, csv_file, position_type)
      CSV.open(csv_file, "w") do |csv|
        headers = %w[symbol security_id side entry_price quantity current_price pnl pnl_percentage
                     option_type strike expiry timestamp]

        headers += %w[exit_price exit_reason exit_timestamp] if position_type == "closed"

        csv << headers

        positions.each do |position|
          row = [
            position[:symbol],
            position[:security_id],
            position[:side],
            position[:entry_price],
            position[:quantity],
            position[:current_price],
            position[:pnl],
            position[:pnl_percentage],
            position[:option_type],
            position[:strike],
            position[:expiry],
            position[:timestamp]
          ]

          if position_type == "closed"
            row += [
              position[:exit_price],
              position[:exit_reason],
              position[:exit_timestamp]
            ]
          end

          csv << row
        end
      end

      @logger.info "[REPORT] #{position_type.capitalize} positions saved to #{csv_file}"
    end

    def print_console_summary(report_data)
      puts "\n" + ("=" * 60)
      puts "DHAN SCALPER - SESSION REPORT"
      puts "=" * 60

      # Session information
      puts "Session ID: #{report_data[:session_id]}"
      puts "Duration: #{report_data[:duration_minutes].round(1)} minutes"
      puts "Start: #{report_data[:session_start]}"
      puts "End: #{report_data[:session_end]}"
      puts

      # Trading statistics
      puts "TRADING STATISTICS:"
      puts "  Total Trades: #{report_data[:total_trades]}"
      puts "  Winning Trades: #{report_data[:winning_trades]}"
      puts "  Losing Trades: #{report_data[:losing_trades]}"
      puts "  Win Rate: #{report_data[:win_rate].round(1)}%"
      puts

      # P&L statistics
      puts "P&L STATISTICS:"
      puts "  Total P&L: ₹#{report_data[:total_pnl].round(2)}"
      puts "  Max Profit: ₹#{report_data[:max_profit].round(2)}"
      puts "  Max Drawdown: ₹#{report_data[:max_drawdown].round(2)}"
      puts

      # Position statistics
      puts "POSITION STATISTICS:"
      puts "  Open Positions: #{report_data[:open_positions]}"
      puts "  Closed Positions: #{report_data[:closed_positions]}"
      puts

      # Balance information
      puts "BALANCE INFORMATION:"
      puts "  Starting Balance: ₹#{report_data[:starting_balance].round(2)}"
      puts "  Final Balance: ₹#{report_data[:final_balance].round(2)}"
      puts "  Balance Change: ₹#{report_data[:balance_change].round(2)}"
      puts "  Balance Change: #{report_data[:balance_change_pct].round(2)}%"
      puts

      puts "=" * 60
      puts "Report files saved to: #{@data_dir}/"
      puts "=" * 60
    end

    def ensure_data_directory
      FileUtils.mkdir_p(@data_dir)
    end
  end
end
