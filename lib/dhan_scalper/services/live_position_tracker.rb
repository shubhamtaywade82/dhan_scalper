# frozen_string_literal: true

module DhanScalper
  module Services
    class LivePositionTracker
      def initialize(broker:, balance_provider:, logger: Logger.new($stdout))
        @broker = broker
        @balance_provider = balance_provider
        @logger = logger
        @positions = {}
        @last_sync = Time.now
        @sync_interval = 30 # seconds
      end

      def get_positions
        sync_positions_if_needed
        @positions.values
      end

      def get_position(security_id)
        sync_positions_if_needed
        @positions[security_id]
      end

      def get_total_pnl
        sync_positions_if_needed
        @positions.values.sum { |pos| pos[:pnl] || 0.0 }
      end

      def get_open_positions
        sync_positions_if_needed
        @positions.values.select { |pos| pos[:quantity] && pos[:quantity] != 0 }
      end

      def update_position(security_id, updates)
        sync_positions_if_needed
        return unless @positions[security_id]

        @positions[security_id].merge!(updates)
        @logger.debug "[LIVE_POSITION_TRACKER] Updated position #{security_id}: #{updates}"
      end

      def close_position(security_id)
        sync_positions_if_needed
        position = @positions[security_id]
        return false unless position

        @positions.delete(security_id)
        @logger.info "[LIVE_POSITION_TRACKER] Closed position #{security_id}"
        true
      end

      private

      def sync_positions_if_needed
        return if Time.now - @last_sync < @sync_interval

        begin
          positions = @broker.get_positions
          return unless positions

          @positions = {}
          positions.each do |pos|
            @positions[pos[:security_id]] = {
              security_id: pos[:security_id],
              symbol: pos[:symbol],
              quantity: pos[:quantity],
              average_price: pos[:average_price],
              current_price: pos[:current_price],
              pnl: pos[:pnl],
              pnl_percentage: pos[:pnl_percentage],
              last_updated: Time.now
            }
          end

          @last_sync = Time.now
          @logger.debug "[LIVE_POSITION_TRACKER] Synced #{@positions.size} positions"
        rescue StandardError => e
          @logger.error "[LIVE_POSITION_TRACKER] Error syncing positions: #{e.message}"
        end
      end
    end
  end
end