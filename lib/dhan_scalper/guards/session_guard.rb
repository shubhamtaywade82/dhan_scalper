# frozen_string_literal: true

require_relative "../support/application_service"

module DhanScalper
  module Guards
    # Session guard for market hours, day loss protection, and panic switch
    class SessionGuard < DhanScalper::ApplicationService
      attr_reader :config, :position_tracker, :cache, :logger

      def initialize(config:, position_tracker:, cache:, logger: nil)
        @config = config
        @position_tracker = position_tracker
        @cache = cache
        @logger = logger || Logger.new($stdout)
      end

      def call
        return :panic_switch if panic_switch_active?
        return :market_closed unless market_open?
        return :day_loss_limit if day_loss_limit_breached?
        return :feed_stale if feed_stale?

        :ok
      end

      def force_exit_all
        @logger.warn "[SESSION_GUARD] Force exiting all positions due to panic switch or day loss limit"

        open_positions = @position_tracker.get_open_positions
        return :no_positions if open_positions.empty?

        results = []
        open_positions.each do |position|
          result = force_exit_position(position)
          results << result
        end

        results
      end

      private

      def panic_switch_active?
        ENV["PANIC"] == "true" || ENV["EMERGENCY"] == "true"
      end

      def market_open?
        current_time = Time.now
        market_start = Time.parse("09:15")
        market_end = Time.parse("15:30")

        # Add grace period
        grace_start = market_start - 5.minutes
        grace_end = market_end + 5.minutes

        current_time.between?(grace_start, grace_end)
      end

      def day_loss_limit_breached?
        max_day_loss = @config.dig("risk", "max_day_loss_rupees")&.to_f
        return false unless max_day_loss&.positive?

        total_pnl = @position_tracker.get_total_pnl
        total_pnl <= -max_day_loss
      end

      def feed_stale?
        heartbeat_key = "feed:heartbeat"
        last_heartbeat = @cache.get(heartbeat_key)

        return true unless last_heartbeat

        last_heartbeat_time = Time.parse(last_heartbeat)
        stale_threshold = 60 # seconds

        (Time.now - last_heartbeat_time) > stale_threshold
      end

      def force_exit_position(position)
        @logger.warn "[SESSION_GUARD] Force exiting position: #{position[:symbol]} #{position[:security_id]}"

        # This would place a market exit order
        # For now, just log the action
        puts "[FORCE_EXIT] #{position[:symbol]} #{position[:security_id]} - Market order"

        :force_exit_placed
      end

      def update_heartbeat
        heartbeat_key = "feed:heartbeat"
        @cache.set(heartbeat_key, Time.now.iso8601, ttl: 120) # 2 minutes TTL
      end
    end
  end
end
