# frozen_string_literal: true

require "concurrent"
require "DhanHQ"

module DhanScalper
  module Services
    class OrderMonitor
      def initialize(broker, position_tracker, logger: nil)
        @broker = broker
        @position_tracker = position_tracker
        @logger = logger || Logger.new($stdout)
        @running = false
        @monitor_thread = nil
        @pending_orders = Concurrent::Map.new
        @check_interval = 5 # Check every 5 seconds
      end

      def start
        return if @running

        @running = true
        @monitor_thread = Thread.new { monitor_loop }
        @logger.info "[ORDER_MONITOR] Started monitoring pending orders"
      end

      def stop
        return unless @running

        @running = false
        @monitor_thread&.join
        @logger.info "[ORDER_MONITOR] Stopped monitoring"
      end

      def add_pending_order(order_id, order_data)
        @pending_orders[order_id] = {
          order_data: order_data,
          created_at: Time.now,
          last_checked: Time.now
        }
        @logger.debug "[ORDER_MONITOR] Added pending order: #{order_id}"
      end

      def remove_pending_order(order_id)
        @pending_orders.delete(order_id)
        @logger.debug "[ORDER_MONITOR] Removed order: #{order_id}"
      end

      def get_pending_orders
        @pending_orders.keys
      end

      private

      def monitor_loop
        @logger.info "[ORDER_MONITOR] Starting order monitoring loop"

        while @running
          begin
            check_pending_orders
            sleep(@check_interval)
          rescue StandardError => e
            @logger.error "[ORDER_MONITOR] Error in monitoring loop: #{e.message}"
            sleep(@check_interval)
          end
        end
      rescue StandardError => e
        @logger.error "[ORDER_MONITOR] Fatal error in monitoring loop: #{e.message}"
        @logger.error "[ORDER_MONITOR] Backtrace: #{e.backtrace.first(3).join("\n")}"
      end

      def check_pending_orders
        return if @pending_orders.empty?

        @pending_orders.each do |order_id, order_info|
          check_order_status(order_id, order_info)
        end
      end

      def check_order_status(order_id, order_info)
        # Get order status from broker
        order_status = @broker.get_order_status(order_id)
        return unless order_status

        @logger.debug "[ORDER_MONITOR] Order #{order_id} status: #{order_status[:status]}"

        case order_status[:status]&.downcase
        when "complete", "filled"
          handle_filled_order(order_id, order_info, order_status)
        when "rejected", "cancelled", "failed"
          handle_failed_order(order_id, order_info, order_status)
        when "pending", "open"
          # Order still pending, update last checked time
          order_info[:last_checked] = Time.now
        else
          @logger.warn "[ORDER_MONITOR] Unknown order status for #{order_id}: #{order_status[:status]}"
        end
      rescue StandardError => e
        @logger.error "[ORDER_MONITOR] Error checking order #{order_id}: #{e.message}"
      end

      def handle_filled_order(order_id, order_info, order_status)
        @logger.info "[ORDER_MONITOR] Order #{order_id} filled successfully"

        # Update position tracker with filled order
        order_data = order_info[:order_data]
        fill_price = order_status[:fill_price] || order_data[:price]
        fill_quantity = order_status[:fill_quantity] || order_data[:quantity]

        # Add position to tracker
        @position_tracker.add_position(
          order_data[:symbol],
          order_data[:option_type],
          order_data[:strike],
          order_data[:expiry],
          order_id,
          fill_quantity,
          fill_price
        )

        # Remove from pending orders
        remove_pending_order(order_id)
      end

      def handle_failed_order(order_id, _order_info, order_status)
        @logger.warn "[ORDER_MONITOR] Order #{order_id} failed: #{order_status[:status]}"
        @logger.warn "[ORDER_MONITOR] Reason: #{order_status[:reason] || "Unknown"}"

        # Remove from pending orders
        remove_pending_order(order_id)
      end

      def cleanup_old_orders
        # Remove orders older than 1 hour
        cutoff_time = Time.now - 3600
        @pending_orders.each do |order_id, order_info|
          if order_info[:created_at] < cutoff_time
            @logger.warn "[ORDER_MONITOR] Removing old pending order: #{order_id}"
            remove_pending_order(order_id)
          end
        end
      end
    end
  end
end
