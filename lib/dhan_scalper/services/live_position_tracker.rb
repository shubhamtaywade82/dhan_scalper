# frozen_string_literal: true

module DhanScalper
  module Services
    class LivePositionTracker
      attr_reader :positions, :websocket_manager

      def initialize(broker:, balance_provider:, logger: Logger.new($stdout), websocket_manager: nil)
        @broker = broker
        @balance_provider = balance_provider
        @logger = logger
        @websocket_manager = websocket_manager
        @positions = {}
        @last_sync = Time.now
        @sync_interval = 30 # seconds
        @security_to_strike = {} # For mapping security IDs to strike info
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

      # Load existing positions from DhanHQ and subscribe to them
      def load_existing_positions
        @logger.info '[LIVE_POSITION_TRACKER] Loading existing positions from DhanHQ...'

        begin
          # Get all positions from DhanHQ
          positions = @broker.get_positions
          return if positions.nil? || positions.empty?

          @logger.info "[LIVE_POSITION_TRACKER] Found #{positions.size} existing positions"

          positions.each do |position_data|
            security_id = position_data[:security_id]
            symbol = position_data[:symbol]
            quantity = position_data[:quantity]
            average_price = position_data[:average_price]

            # Skip if position is closed (quantity is 0 or negative)
            next if quantity.to_i <= 0

            # Store position in our cache
            @positions[security_id] = {
              security_id: security_id,
              symbol: symbol,
              quantity: quantity,
              average_price: average_price,
              current_price: position_data[:current_price] || average_price,
              pnl: position_data[:pnl] || 0.0,
              pnl_percentage: position_data[:pnl_percentage] || 0.0,
              last_updated: Time.now
            }

            # Subscribe to WebSocket for real-time updates if websocket_manager is available
            if @websocket_manager
              @websocket_manager.subscribe_to_instrument(security_id, 'OPTION')
              @logger.debug "[LIVE_POSITION_TRACKER] Subscribed to #{security_id} for real-time updates"
            end

            @logger.info "  ✅ Loaded position: #{symbol} (#{quantity} lots @ ₹#{average_price}) [#{security_id}]"
          rescue StandardError => e
            @logger.error "  ❌ Failed to load position #{position_data[:symbol]}: #{e.message}"
            @logger.debug "    Error details: #{e.backtrace.first(2).join("\n")}"
          end

          @logger.info "[LIVE_POSITION_TRACKER] Position loading complete - #{@positions.size} positions loaded"
        rescue StandardError => e
          @logger.error "[LIVE_POSITION_TRACKER] Error loading positions from DhanHQ: #{e.message}"
          @logger.debug "    Error details: #{e.backtrace.first(3).join("\n")}"
        end
      end

      # Get positions summary for reporting
      def get_positions_summary
        sync_positions_if_needed

        total_positions = @positions.size
        total_pnl = @positions.values.sum { |pos| pos[:pnl] || 0.0 }

        # Handle empty positions array to avoid nil comparison errors
        pnl_values = @positions.values.map { |pos| pos[:pnl] || 0.0 }
        max_profit = pnl_values.empty? ? 0.0 : pnl_values.max
        max_drawdown = pnl_values.empty? ? 0.0 : pnl_values.min

        {
          total_positions: total_positions,
          total_pnl: total_pnl,
          max_profit: max_profit,
          max_drawdown: max_drawdown,
          positions: @positions
        }
      end

      # Get underlying summary for display
      def get_underlying_summary
        # For live mode, we don't track underlying prices separately
        # This is handled by the market feed
        {}
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
