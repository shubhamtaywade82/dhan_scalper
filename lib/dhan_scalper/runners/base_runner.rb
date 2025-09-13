# frozen_string_literal: true

require "logger"
require "ostruct"

module DhanScalper
  module Runners
    # Base runner class that contains common functionality between App and PaperApp
    class BaseRunner
      attr_reader :config, :mode, :quiet, :enhanced, :stop, :state, :balance_provider, :broker, :quantity_sizer

      def initialize(config, mode: :paper, quiet: false, enhanced: true)
        @config = config
        @mode = mode
        @quiet = quiet
        @enhanced = enhanced
        @stop = false
        @start_time = Time.now

        setup_signal_handlers
        initialize_state
        initialize_balance_provider
        initialize_quantity_sizer
        initialize_broker
      end

      def start
        raise NotImplementedError, "Subclasses must implement #start"
      end

      def stop
        @stop = true
      end

      def running?
        !@stop
      end

      protected

      def setup_signal_handlers
        Signal.trap("INT") { @stop = true }
        Signal.trap("TERM") { @stop = true }
      end

      def initialize_state
        @state = State.new(
          symbols: @config["SYMBOLS"]&.keys || [],
          session_target: @config.dig("global", "min_profit_target").to_f,
          max_day_loss: @config.dig("global", "max_day_loss").to_f
        )
      end

      def initialize_balance_provider
        @balance_provider = if @mode == :paper
                              starting_balance = @config.dig("paper", "starting_balance") || 200_000.0
                              BalanceProviders::PaperWallet.new(starting_balance: starting_balance)
                            else
                              BalanceProviders::LiveBalance.new
                            end
      end

      def initialize_quantity_sizer
        @quantity_sizer = QuantitySizer.new(@config, @balance_provider)
      end

      def initialize_broker
        @broker = if @mode == :paper
                    Brokers::PaperBroker.new(
                      virtual_data_manager: @virtual_data_manager,
                      balance_provider: @balance_provider
                    )
                  else
                    Brokers::DhanBroker.new(
                      virtual_data_manager: @virtual_data_manager,
                      balance_provider: @balance_provider
                    )
                  end
      end

      def initialize_virtual_data_manager
        @virtual_data_manager = VirtualDataManager.new(memory_only: @mode == :paper)
      end

      def display_startup_info
        puts "[READY] Symbols: #{@config["SYMBOLS"]&.keys&.join(", ") || "None"}"
        puts "[MODE] #{@mode.upcase} trading with balance: ₹#{@balance_provider.available_balance.round(0)}"
        puts "[QUIET] Running in quiet mode - minimal output" if @quiet
        puts "[CONTROLS] Press Ctrl+C to stop"
      end

      def check_risk_limits
        # Check daily loss limit
        total_pnl = get_total_pnl
        max_loss = @config.dig("global", "max_day_loss").to_f

        if total_pnl < -max_loss
          puts "\n[HALT] Max day loss hit (#{total_pnl.round(0)})."
          @stop = true
          return true
        end

        # Check session target
        if total_pnl >= @state.session_target && no_open_positions?
          puts "\n[DONE] Session target reached: #{total_pnl.round(0)}"
          @stop = true
          return true
        end

        false
      end

      def get_total_pnl
        # This should be implemented by subclasses based on their position tracking
        raise NotImplementedError, "Subclasses must implement #get_total_pnl"
      end

      def no_open_positions?
        # This should be implemented by subclasses based on their position tracking
        raise NotImplementedError, "Subclasses must implement #no_open_positions?"
      end

      def get_decision_interval
        @config.dig("global", "decision_interval_sec") ||
        @config.dig("global", "decision_interval") ||
        60
      end

      def get_status_interval
        @config.dig("global", "log_status_every") || 60
      end

      def get_risk_loop_interval
        @config.dig("global", "risk_loop_interval_sec") || 1.0
      end

      def get_charge_per_order
        @config.dig("global", "charge_per_order") || 20.0
      end

      def get_tp_pct
        @config.dig("global", "tp_pct") || 0.35
      end

      def get_sl_pct
        @config.dig("global", "sl_pct") || 0.18
      end

      def get_trail_pct
        @config.dig("global", "trail_pct") || 0.12
      end

      def sym_cfg(sym)
        @config.fetch("SYMBOLS").fetch(sym)
      end

      def log_error(error)
        puts "\n[ERR] #{error.class}: #{error.message}"
        puts error.backtrace.first(5).join("\n") if @config.dig("global", "log_level") == "DEBUG"
      end

      def log_status
        return unless @quiet

        puts "[#{Time.now.strftime("%H:%M:%S")}] Status: #{@state.status} | PnL: ₹#{get_total_pnl} | Balance: ₹#{@balance_provider.available_balance.round(0)} (Used: ₹#{@balance_provider.used_balance.round(0)})"
      end

      def cleanup
        @state.set_status(:stopped)
        puts "\n[#{@mode.upcase}] Trading stopped"
      end
    end
  end
end
