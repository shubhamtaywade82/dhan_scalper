# frozen_string_literal: true

require_relative "../support/application_service"

module DhanScalper
  module Managers
    # Exit manager for handling position exits and adjustments
    class ExitManager < DhanScalper::ApplicationService
      attr_reader :config, :no_loss_trend_rider, :order_manager, :position_tracker

      def initialize(config:, no_loss_trend_rider:, order_manager:, position_tracker:)
        @config = config
        @no_loss_trend_rider = no_loss_trend_rider
        @order_manager = order_manager
        @position_tracker = position_tracker
      end

      def call
        open_positions = @position_tracker.get_open_positions
        return :no_positions if open_positions.empty?

        results = []

        open_positions.each do |position|
          result = process_position(position)
          results << result if result != :noop
        end

        results
      end

      private

      def process_position(position)
        # Use No-Loss Trend Rider to determine action
        action = @no_loss_trend_rider.call(position)

        case action
        when :noop
          :noop
        when :duplicate
          :duplicate
        else
          execute_exit_action(position, action)
        end
      end

      def execute_exit_action(position, action)
        case action[:type]
        when :emergency_exit, :initial_sl_exit, :breakeven_lock_exit, :trailing_stop_exit
          place_exit_order(position, action)
        when :adjust_trailing_stop
          adjust_stop_loss(position, action)
        else
          :unknown_action
        end
      end

      def place_exit_order(position, action)
        order_data = {
          symbol: position[:symbol],
          security_id: position[:security_id],
          side: position[:side] == "BUY" ? "SELL" : "BUY", # Opposite side
          quantity: position[:quantity],
          price: action[:price],
          order_type: "MARKET",
          reason: action[:reason],
          exit_type: action[:type]
        }

        result = @order_manager.place_order(order_data)

        if result[:success]
          puts "[EXIT] #{action[:type].to_s.upcase}: #{action[:reason]} - P&L: ₹#{action[:pnl].round(2)}"
          :exit_placed
        else
          puts "[EXIT] Failed to place exit order: #{result[:error]}"
          :exit_failed
        end
      end

      def adjust_stop_loss(position, action)
        # This would modify the existing stop loss order
        # For now, just log the adjustment
        puts "[ADJUST] #{action[:reason]}"
        puts "  Old trigger: ₹#{action[:old_trigger]&.round(2)}"
        puts "  New trigger: ₹#{action[:new_trigger]&.round(2)}"
        puts "  Peak price: ₹#{action[:peak_price]&.round(2)}"

        :stop_adjusted
      end
    end
  end
end
