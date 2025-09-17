# frozen_string_literal: true

require_relative '../support/application_service'

module DhanScalper
  module Services
    # Service to manage trading day-based sessions
    class TradingDayService < DhanScalper::ApplicationService
      attr_reader :config, :logger

      def initialize(config:, logger: nil)
        super()
        @config = config
        @logger = logger || Logger.new($stdout)
      end

      def call
        current_trading_day
      end

      # Get the current trading day
      # @return [String] Trading day in YYYYMMDD format
      def current_trading_day
        today = Date.today

        # If it's weekend, use the last trading day (Friday)
        if today.saturday?
          (today - 1).strftime('%Y%m%d')
        elsif today.sunday?
          (today - 2).strftime('%Y%m%d')
        else
          today.strftime('%Y%m%d')
        end
      end

      # Get the current trading day with mode prefix
      # @param mode [String] Trading mode (paper, live, etc.)
      # @return [String] Session ID in format MODE_YYYYMMDD
      def current_session_id(mode: 'PAPER')
        "#{mode.upcase}_#{current_trading_day}"
      end

      # Check if we're currently in a trading day
      # @return [Boolean] true if it's a trading day
      def trading_day?
        today = Date.today
        !today.saturday? && !today.sunday?
      end

      # Get the next trading day
      # @return [String] Next trading day in YYYYMMDD format
      def next_trading_day
        today = Date.today

        # Find next weekday
        next_day = today + 1
        next_day += 1 while next_day.saturday? || next_day.sunday?

        next_day.strftime('%Y%m%d')
      end

      # Get the previous trading day
      # @return [String] Previous trading day in YYYYMMDD format
      def previous_trading_day
        today = Date.today

        # Find previous weekday
        prev_day = today - 1
        prev_day -= 1 while prev_day.saturday? || prev_day.sunday?

        prev_day.strftime('%Y%m%d')
      end

      # Check if a session exists for the current trading day
      # @param mode [String] Trading mode
      # @param reports_dir [String] Reports directory path
      # @return [Boolean] true if session exists
      def session_exists?(mode: 'PAPER', reports_dir: 'data/reports')
        session_id = current_session_id(mode: mode)
        json_file = File.join(reports_dir, "#{session_id}.json")
        File.exist?(json_file)
      end

      # Get existing session data for the current trading day
      # @param mode [String] Trading mode
      # @param reports_dir [String] Reports directory path
      # @return [Hash, nil] Session data or nil if not found
      def get_existing_session(mode: 'PAPER', reports_dir: 'data/reports')
        session_id = current_session_id(mode: mode)
        json_file = File.join(reports_dir, "#{session_id}.json")

        return nil unless File.exist?(json_file)

        session_data = JSON.parse(File.read(json_file), symbolize_names: true)

        # Convert symbols_traded from Array to Set if needed
        if session_data[:symbols_traded].is_a?(Array)
          session_data[:symbols_traded] = Set.new(session_data[:symbols_traded])
        end

        session_data
      rescue StandardError => e
        @logger.error("[TRADING_DAY] Error loading existing session: #{e.message}")
        nil
      end

      # Initialize session data for the current trading day
      # @param mode [String] Trading mode
      # @param starting_balance [Float] Starting balance
      # @return [Hash] Initialized session data
      def initialize_session_data(mode: 'PAPER', starting_balance: 200_000.0)
        session_id = current_session_id(mode: mode)
        current_time = Time.now

        {
          session_id: session_id,
          trading_day: current_trading_day,
          start_time: current_time.strftime('%Y-%m-%d %H:%M:%S'),
          end_time: nil,
          duration_minutes: 0.0,
          mode: mode.downcase,
          starting_balance: starting_balance,
          ending_balance: starting_balance,
          available_balance: starting_balance,
          used_balance: 0.0,
          total_balance: starting_balance,
          total_trades: 0,
          successful_trades: 0,
          failed_trades: 0,
          total_pnl: 0.0,
          max_drawdown: 0.0,
          max_profit: 0.0,
          max_pnl: 0.0,
          min_pnl: 0.0,
          win_rate: 0.0,
          average_trade_pnl: 0.0,
          symbols_traded: Set.new,
          positions: [],
          trades: [],
          risk_metrics: {},
          performance_summary: {}
        }
      end

      # Load or create session data for the current trading day
      # @param mode [String] Trading mode
      # @param starting_balance [Float] Starting balance
      # @param reports_dir [String] Reports directory path
      # @return [Hash] Session data (existing or new)
      def load_or_create_session(mode: 'PAPER', starting_balance: 200_000.0, reports_dir: 'data/reports')
        existing_session = get_existing_session(mode: mode, reports_dir: reports_dir)

        if existing_session
          @logger.info("[TRADING_DAY] Resuming existing session: #{existing_session[:session_id]}")
          existing_session
        else
          @logger.info("[TRADING_DAY] Creating new session for trading day: #{current_trading_day}")
          initialize_session_data(mode: mode, starting_balance: starting_balance)
        end
      end

      # Update session end time and duration
      # @param session_data [Hash] Session data to update
      # @return [Hash] Updated session data
      def finalize_session(session_data)
        return {} unless session_data

        current_time = Time.now
        start_time = session_data[:start_time] ? Time.parse(session_data[:start_time]) : current_time

        session_data.merge(
          end_time: current_time.strftime('%Y-%m-%d %H:%M:%S'),
          duration_minutes: (current_time - start_time) / 60.0
        )
      end

      # Get all trading days in a date range
      # @param start_date [Date] Start date
      # @param end_date [Date] End date
      # @return [Array<String>] Array of trading days in YYYYMMDD format
      def trading_days_in_range(start_date, end_date)
        trading_days = []
        current_date = start_date

        while current_date <= end_date
          trading_days << current_date.strftime('%Y%m%d') unless current_date.saturday? || current_date.sunday?
          current_date += 1
        end

        trading_days
      end

      # Get session files for a specific trading day
      # @param trading_day [String] Trading day in YYYYMMDD format
      # @param mode [String] Trading mode
      # @param reports_dir [String] Reports directory path
      # @return [Array<String>] Array of session file paths
      def get_session_files(trading_day, mode: 'PAPER', reports_dir: 'data/reports')
        session_id = "#{mode.upcase}_#{trading_day}"
        json_file = File.join(reports_dir, "#{session_id}.json")
        csv_file = File.join(reports_dir, "#{session_id}.csv")

        files = []
        files << json_file if File.exist?(json_file)
        files << csv_file if File.exist?(csv_file)
        files
      end
    end
  end
end
