# frozen_string_literal: true

module DhanScalper
  module Services
    class LiveOrderManager
      def initialize(broker:, position_tracker:, logger: Logger.new($stdout))
        @broker = broker
        @position_tracker = position_tracker
        @logger = logger
        @orders = {}
        @last_sync = Time.now
        @sync_interval = 30 # seconds
      end

      def place_order(symbol:, instrument_id:, side:, quantity:, price:, order_type: "MARKET")
        @logger.info "[LIVE_ORDER_MANAGER] Placing #{side} order for #{symbol}: #{quantity} @ #{price}"

        result = @broker.place_order(
          symbol: symbol,
          instrument_id: instrument_id,
          side: side,
          quantity: quantity,
          price: price,
          order_type: order_type,
        )

        if result[:success]
          @logger.info "[LIVE_ORDER_MANAGER] Order placed successfully: #{result[:order_id]}"
          @orders[result[:order_id]] = {
            order_id: result[:order_id],
            symbol: symbol,
            instrument_id: instrument_id,
            side: side,
            quantity: quantity,
            price: price,
            order_type: order_type,
            status: "PENDING",
            created_at: Time.now,
          }
        else
          @logger.error "[LIVE_ORDER_MANAGER] Failed to place order: #{result[:error]}"
        end
        result
      rescue StandardError => e
        @logger.error "[LIVE_ORDER_MANAGER] Error placing order: #{e.message}"
        { success: false, error: e.message }
      end

      def cancel_order(order_id)
        @logger.info "[LIVE_ORDER_MANAGER] Cancelling order: #{order_id}"

        success = @broker.cancel_order(order_id)
        if success
          @logger.info "[LIVE_ORDER_MANAGER] Order cancelled successfully: #{order_id}"
          @orders.delete(order_id)
          true
        else
          @logger.error "[LIVE_ORDER_MANAGER] Failed to cancel order: #{order_id}"
          false
        end
      rescue StandardError => e
        @logger.error "[LIVE_ORDER_MANAGER] Error cancelling order: #{e.message}"
        false
      end

      def get_orders(status: nil)
        sync_orders_if_needed
        orders = @orders.values
        return orders unless status

        orders.select { |order| order[:status] == status }
      end

      def get_order(order_id)
        sync_orders_if_needed
        @orders[order_id]
      end

      def get_pending_orders
        get_orders(status: "PENDING")
      end

      def get_filled_orders
        get_orders(status: "FILLED")
      end

      def get_cancelled_orders
        get_orders(status: "CANCELLED")
      end

      def get_rejected_orders
        get_orders(status: "REJECTED")
      end

      def get_order_status(order_id)
        status = @broker.get_order_status(order_id)
        return nil unless status

        # Update local cache
        if @orders[order_id]
          @orders[order_id][:status] = status[:status]
          @orders[order_id][:fill_price] = status[:fill_price]
          @orders[order_id][:fill_quantity] = status[:fill_quantity]
          @orders[order_id][:reason] = status[:reason]
          @orders[order_id][:last_updated] = Time.now
        end

        status
      rescue StandardError => e
        @logger.error "[LIVE_ORDER_MANAGER] Error fetching order status: #{e.message}"
        nil
      end

      def get_trades(order_id: nil, from_date: nil, to_date: nil)
        @broker.get_trades(order_id: order_id, from_date: from_date, to_date: to_date)
      rescue StandardError => e
        @logger.error "[LIVE_ORDER_MANAGER] Error fetching trades: #{e.message}"
        []
      end

      def get_funds
        @broker.get_funds
      rescue StandardError => e
        @logger.error "[LIVE_ORDER_MANAGER] Error fetching funds: #{e.message}"
        nil
      end

      def get_holdings
        @broker.get_holdings
      rescue StandardError => e
        @logger.error "[LIVE_ORDER_MANAGER] Error fetching holdings: #{e.message}"
        []
      end

      private

      def sync_orders_if_needed
        return if Time.now - @last_sync < @sync_interval

        begin
          orders = @broker.get_orders
          return unless orders

          @orders = {}
          orders.each do |order|
            @orders[order[:order_id]] = {
              order_id: order[:order_id],
              symbol: order[:symbol],
              instrument_id: order[:security_id],
              side: order[:side],
              quantity: order[:quantity],
              price: order[:price],
              order_type: order[:order_type],
              status: order[:status],
              created_at: order[:created_at],
              last_updated: Time.now,
            }
          end

          @last_sync = Time.now
          @logger.debug "[LIVE_ORDER_MANAGER] Synced #{@orders.size} orders"
        rescue StandardError => e
          @logger.error "[LIVE_ORDER_MANAGER] Error syncing orders: #{e.message}"
        end
      end
    end
  end
end
