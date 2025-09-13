# frozen_string_literal: true

require_relative "../support/application_service"

module DhanScalper
  module Services
    # Service to handle market hours checking with toggleable enforcement
    class MarketHoursService < DhanScalper::ApplicationService
      attr_reader :config, :logger

      def initialize(config:, logger: nil)
        @config = config
        @logger = logger || Logger.new($stdout)
      end

      def call
        market_open?
      end

      # Check if market is currently open
      # @return [Boolean] true if market is open or if market hours enforcement is disabled
      def market_open?
        return true unless market_hours_enforced?

        current_time = Time.now
        current_date = current_time.to_date

        # Check if it's a weekend
        return false if current_time.saturday? || current_time.sunday?

        # Get market hours from config or use defaults
        session_hours = @config.dig("global", "session_hours") || ["09:15", "15:30"]
        start_time_str, end_time_str = session_hours

        # Parse market hours
        market_start = Time.new(current_date.year, current_date.month, current_date.day,
                               start_time_str.split(":")[0].to_i,
                               start_time_str.split(":")[1].to_i, 0)
        market_end = Time.new(current_date.year, current_date.month, current_date.day,
                             end_time_str.split(":")[0].to_i,
                             end_time_str.split(":")[1].to_i, 0)

        # Check if current time is within market hours
        is_open = current_time.between?(market_start, market_end)

        @logger.debug "[MARKET_HOURS] Market #{is_open ? 'open' : 'closed'} (#{current_time.strftime('%H:%M:%S')} between #{start_time_str}-#{end_time_str})" if @logger
        is_open
      end

      # Check if market hours enforcement is enabled
      # @return [Boolean] true if market hours should be enforced
      def market_hours_enforced?
        # Check environment variable first
        env_setting = ENV["ENFORCE_MARKET_HOURS"]
        return env_setting.downcase == "true" if env_setting

        # Check config setting
        config_setting = @config.dig("global", "enforce_market_hours")
        return config_setting == true if !config_setting.nil?

        # Default to true (enforce market hours)
        true
      end

      # Get market status message
      # @return [String] Human-readable market status
      def market_status
        if market_hours_enforced?
          market_open? ? "Market is OPEN" : "Market is CLOSED"
        else
          "Market hours enforcement DISABLED - trading allowed 24/7"
        end
      end

      # Get time until market opens (if closed)
      # @return [String, nil] Time until market opens or nil if open
      def time_until_market_opens
        return nil if market_open? || !market_hours_enforced?

        current_time = Time.now
        current_date = current_time.to_date

        # Get next trading day (skip weekends)
        next_trading_date = current_date
        loop do
          next_trading_date += 1
          break unless next_trading_date.saturday? || next_trading_date.sunday?
        end

        # Get market start time
        session_hours = @config.dig("global", "session_hours") || ["09:15", "15:30"]
        start_time_str = session_hours[0]

        next_market_open = Time.new(next_trading_date.year, next_trading_date.month, next_trading_date.day,
                                   start_time_str.split(":")[0].to_i,
                                   start_time_str.split(":")[1].to_i, 0)

        # If it's the same day and we're before market close, market opens tomorrow
        if current_date == next_trading_date && current_time.hour < 15
          next_market_open = Time.new(current_date.year, current_date.month, current_date.day,
                                     start_time_str.split(":")[0].to_i,
                                     start_time_str.split(":")[1].to_i, 0)
        end

        time_diff = next_market_open - current_time
        hours = (time_diff / 3600).to_i
        minutes = ((time_diff % 3600) / 60).to_i

        "#{hours}h #{minutes}m"
      end
    end
  end
end
