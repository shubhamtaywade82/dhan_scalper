# frozen_string_literal: true

require 'concurrent'
require 'DhanHQ'

module DhanScalper
  module Services
    class PositionReconciler
      def initialize(broker, position_tracker, logger: nil)
        @broker = broker
        @position_tracker = position_tracker
        @logger = logger || Logger.new($stdout)
        @running = false
        @reconcile_thread = nil
        @reconcile_interval = 300 # Reconcile every 5 minutes
      end

      def start
        return if @running

        @running = true
        @reconcile_thread = Thread.new { reconcile_loop }
        @logger.info '[POSITION_RECONCILER] Started position reconciliation'
      end

      def stop
        return unless @running

        @running = false
        @reconcile_thread&.join
        @logger.info '[POSITION_RECONCILER] Stopped reconciliation'
      end

      def reconcile_now
        @logger.info '[POSITION_RECONCILER] Starting manual reconciliation'
        reconcile_positions
      end

      private

      def reconcile_loop
        @logger.info '[POSITION_RECONCILER] Starting reconciliation loop'

        while @running
          begin
            reconcile_positions
            sleep(@reconcile_interval)
          rescue StandardError => e
            @logger.error "[POSITION_RECONCILER] Error in reconciliation loop: #{e.message}"
            sleep(@reconcile_interval)
          end
        end
      rescue StandardError => e
        @logger.error "[POSITION_RECONCILER] Fatal error in reconciliation loop: #{e.message}"
        @logger.error "[POSITION_RECONCILER] Backtrace: #{e.backtrace.first(3).join("\n")}"
      end

      def reconcile_positions
        # Get positions from broker (live positions)
        broker_positions = get_broker_positions
        return if broker_positions.nil?

        # Get positions from our tracker
        tracker_positions = @position_tracker.get_open_positions

        @logger.debug "[POSITION_RECONCILER] Broker positions: #{broker_positions.size}, Tracker positions: #{tracker_positions.size}"

        # Find discrepancies
        discrepancies = find_discrepancies(broker_positions, tracker_positions)

        if discrepancies.any?
          @logger.warn "[POSITION_RECONCILER] Found #{discrepancies.size} discrepancies"
          handle_discrepancies(discrepancies)
        else
          @logger.debug '[POSITION_RECONCILER] All positions are in sync'
        end
      rescue StandardError => e
        @logger.error "[POSITION_RECONCILER] Error during reconciliation: #{e.message}"
      end

      def get_broker_positions
        # Get positions from DhanHQ
        positions_response = DhanHQ::Position.get_positions
        return nil unless positions_response&.dig('data')

        positions_data = positions_response['data']
        positions_data.map do |pos|
          {
            security_id: pos['securityId'],
            symbol: pos['symbol'],
            quantity: pos['quantity'].to_i,
            average_price: pos['averagePrice'].to_f,
            current_price: pos['ltp'].to_f,
            pnl: pos['pnl'].to_f,
            product_type: pos['productType'],
            segment: pos['exchangeSegment']
          }
        end
      rescue StandardError => e
        @logger.error "[POSITION_RECONCILER] Error fetching broker positions: #{e.message}"
        nil
      end

      def find_discrepancies(broker_positions, tracker_positions)
        discrepancies = []

        # Check for positions in broker but not in tracker
        broker_positions.each do |broker_pos|
          tracker_pos = tracker_positions.find { |tp| tp[:security_id] == broker_pos[:security_id] }

          if tracker_pos.nil?
            discrepancies << {
              type: :missing_in_tracker,
              broker_position: broker_pos,
              tracker_position: nil
            }
          elsif tracker_pos[:quantity] != broker_pos[:quantity]
            discrepancies << {
              type: :quantity_mismatch,
              broker_position: broker_pos,
              tracker_position: tracker_pos
            }
          end
        end

        # Check for positions in tracker but not in broker
        tracker_positions.each do |tracker_pos|
          broker_pos = broker_positions.find { |bp| bp[:security_id] == tracker_pos[:security_id] }

          next if broker_pos

          discrepancies << {
            type: :missing_in_broker,
            broker_position: nil,
            tracker_position: tracker_pos
          }
        end

        discrepancies
      end

      def handle_discrepancies(discrepancies)
        discrepancies.each do |discrepancy|
          case discrepancy[:type]
          when :missing_in_tracker
            handle_missing_in_tracker(discrepancy[:broker_position])
          when :missing_in_broker
            handle_missing_in_broker(discrepancy[:tracker_position])
          when :quantity_mismatch
            handle_quantity_mismatch(discrepancy[:broker_position], discrepancy[:tracker_position])
          end
        end
      end

      def handle_missing_in_tracker(broker_position)
        @logger.warn "[POSITION_RECONCILER] Position missing in tracker: #{broker_position[:symbol]} #{broker_position[:security_id]}"

        # Add the position to tracker
        @position_tracker.add_position(
          broker_position[:symbol],
          'UNKNOWN', # We don't know if it's CE or PE from broker data
          broker_position[:average_price], # Using average price as strike for now
          'UNKNOWN', # We don't know expiry from broker data
          broker_position[:security_id],
          broker_position[:quantity],
          broker_position[:current_price]
        )

        @logger.info '[POSITION_RECONCILER] Added missing position to tracker'
      end

      def handle_missing_in_broker(tracker_position)
        @logger.warn "[POSITION_RECONCILER] Position missing in broker: #{tracker_position[:symbol]} #{tracker_position[:security_id]}"

        # This could mean the position was closed externally
        # We should close it in our tracker
        @position_tracker.close_position(
          tracker_position[:security_id],
          {
            exit_price: tracker_position[:current_price],
            exit_reason: 'reconciled_missing',
            exit_timestamp: Time.now
          }
        )

        @logger.info '[POSITION_RECONCILER] Closed missing position in tracker'
      end

      def handle_quantity_mismatch(broker_position, tracker_position)
        @logger.warn "[POSITION_RECONCILER] Quantity mismatch for #{broker_position[:symbol]}: " \
                     "Broker: #{broker_position[:quantity]}, Tracker: #{tracker_position[:quantity]}"

        # Update tracker with broker quantity
        @position_tracker.update_position(
          tracker_position[:security_id],
          { quantity: broker_position[:quantity] }
        )

        @logger.info '[POSITION_RECONCILER] Updated quantity in tracker'
      end
    end
  end
end
