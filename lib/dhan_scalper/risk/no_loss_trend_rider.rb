# frozen_string_literal: true

require_relative "../support/application_service"

module DhanScalper
  module Risk
    # No-Loss Trend Rider risk management system
    # Implements sophisticated risk management with emergency floor, breakeven lock, and trailing stops
    class NoLossTrendRider < DhanScalper::ApplicationService
      attr_reader :config, :position_analyzer, :cache

      def initialize(config:, position_analyzer:, cache:)
        @config = config
        @position_analyzer = position_analyzer
        @cache = cache
        @idempotency_window = 10 # seconds
        @recent_actions = {}
      end

      def call(position)
        return :noop unless position&.dig(:security_id)

        analysis = @position_analyzer.analyze(position)
        return :noop unless analysis

        # Check emergency floor first
        return emergency_exit(position, analysis) if emergency_floor_breached?(analysis)

        # Check initial stop loss (before breakeven is armed)
        return initial_stop_loss_exit(position, analysis) if initial_stop_loss_breached?(analysis)

        # Check breakeven lock
        return breakeven_lock_exit(position, analysis) if breakeven_lock_breached?(analysis)

        # Check trailing stop
        return trailing_stop_exit(position, analysis) if trailing_stop_breached?(analysis)

        # Check if we should adjust trailing stop
        return adjust_trailing_stop(position, analysis) if should_adjust_trailing_stop?(analysis)

        :noop
      end

      private

      def emergency_floor_breached?(analysis)
        analysis[:pnl] <= -@config.dig("risk", "emergency_floor_rupees")&.to_f
      end

      def initial_stop_loss_breached?(analysis)
        return false if breakeven_armed?(analysis)

        initial_sl_pct = @config.dig("risk", "initial_sl_pct")&.to_f || 0.02
        analysis[:pnl_pct] <= -initial_sl_pct
      end

      def breakeven_armed?(analysis)
        be_threshold = @config.dig("risk", "breakeven_threshold_pct")&.to_f || 0.15
        analysis[:peak_pct] >= be_threshold
      end

      def breakeven_lock_breached?(analysis)
        return false unless breakeven_armed?(analysis)

        # Once breakeven is armed, never move SL below entry
        analysis[:current_price] < analysis[:entry_price]
      end

      def trailing_stop_breached?(analysis)
        return false unless breakeven_armed?(analysis)

        current_trigger = get_current_trigger(analysis[:security_id])
        return false unless current_trigger

        analysis[:current_price] <= current_trigger
      end

      def should_adjust_trailing_stop?(analysis)
        return false unless breakeven_armed?(analysis)
        return false unless trend_on?(analysis[:security_id])

        peak_price = analysis[:peak_price]
        current_trigger = get_current_trigger(analysis[:security_id])
        return false unless peak_price && current_trigger

        trail_pct = @config.dig("risk", "trail_pct")&.to_f || 0.05
        new_trigger = peak_price * (1 - trail_pct)

        # Only adjust if new trigger is higher and meets rupee step requirement
        new_trigger > current_trigger && meets_rupee_step?(current_trigger, new_trigger)
      end

      def meets_rupee_step?(current_trigger, new_trigger)
        rupee_step = @config.dig("risk", "rupee_step")&.to_f || 3.0
        (new_trigger - current_trigger) >= rupee_step
      end

      def trend_on?(security_id)
        # Check if trend is currently ON for this instrument
        trend_key = "trend:#{security_id}"
        @cache.get(trend_key) == "ON"
      end

      def get_current_trigger(security_id)
        trigger_key = "trigger:#{security_id}"
        @cache.get(trigger_key)&.to_f
      end

      def set_current_trigger(security_id, trigger_price)
        trigger_key = "trigger:#{security_id}"
        @cache.set(trigger_key, trigger_price.to_s, ttl: 3600) # 1 hour TTL
      end

      def emergency_exit(position, analysis)
        action = {
          type: :emergency_exit,
          security_id: position[:security_id],
          reason: "Emergency floor breached: P&L ₹#{analysis[:pnl].round(2)}",
          price: analysis[:current_price],
          pnl: analysis[:pnl]
        }

        execute_action(action)
      end

      def initial_stop_loss_exit(position, analysis)
        action = {
          type: :initial_sl_exit,
          security_id: position[:security_id],
          reason: "Initial stop loss triggered: #{analysis[:pnl_pct].round(2)}%",
          price: analysis[:current_price],
          pnl: analysis[:pnl]
        }

        execute_action(action)
      end

      def breakeven_lock_exit(position, analysis)
        action = {
          type: :breakeven_lock_exit,
          security_id: position[:security_id],
          reason: "Breakeven lock: price below entry",
          price: analysis[:current_price],
          pnl: analysis[:pnl]
        }

        execute_action(action)
      end

      def trailing_stop_exit(position, analysis)
        action = {
          type: :trailing_stop_exit,
          security_id: position[:security_id],
          reason: "Trailing stop triggered",
          price: analysis[:current_price],
          pnl: analysis[:pnl]
        }

        execute_action(action)
      end

      def adjust_trailing_stop(position, analysis)
        peak_price = analysis[:peak_price]
        trail_pct = @config.dig("risk", "trail_pct")&.to_f || 0.05
        new_trigger = peak_price * (1 - trail_pct)

        # Update trigger atomically
        set_current_trigger(position[:security_id], new_trigger)

        action = {
          type: :adjust_trailing_stop,
          security_id: position[:security_id],
          reason: "Adjusted trailing stop to ₹#{new_trigger.round(2)}",
          old_trigger: get_current_trigger(position[:security_id]),
          new_trigger: new_trigger,
          peak_price: peak_price
        }

        execute_action(action)
      end

      def execute_action(action)
        # Check idempotency
        return :duplicate if duplicate_action?(action)

        # Record action for idempotency
        record_action(action)

        # Execute the action
        case action[:type]
        when :emergency_exit, :initial_sl_exit, :breakeven_lock_exit, :trailing_stop_exit
          place_exit_order(action)
        when :adjust_trailing_stop
          adjust_stop_loss(action)
        end

        action
      end

      def duplicate_action?(action)
        key = "#{action[:security_id]}:#{action[:type]}"
        last_action = @recent_actions[key]

        return false unless last_action

        (Time.now - last_action[:timestamp]) < @idempotency_window
      end

      def record_action(action)
        key = "#{action[:security_id]}:#{action[:type]}"
        @recent_actions[key] = {
          timestamp: Time.now,
          action: action
        }

        # Clean up old actions
        cleanup_old_actions
      end

      def cleanup_old_actions
        cutoff_time = Time.now - @idempotency_window
        @recent_actions.reject! { |_key, data| data[:timestamp] < cutoff_time }
      end

      def place_exit_order(action)
        # This would integrate with the order management system
        puts "[RISK] #{action[:type].to_s.upcase}: #{action[:reason]}"
        # TODO: Integrate with OrderManager
      end

      def adjust_stop_loss(action)
        # This would integrate with the order management system
        puts "[RISK] ADJUST: #{action[:reason]}"
        # TODO: Integrate with OrderManager
      end
    end
  end
end
