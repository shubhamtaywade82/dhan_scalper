# frozen_string_literal: true

require "DhanHQ"
require_relative "state"
require_relative "virtual_data_manager"
require_relative "quantity_sizer"
require_relative "balance_providers/paper_wallet"
require_relative "trend_enhanced"
require_relative "option_picker"
require_relative "candle_series"

module DhanScalper
  class DryrunApp
    def initialize(cfg, quiet: false, enhanced: true, once: false)
      @cfg = cfg
      @quiet = quiet
      @enhanced = enhanced
      @once = once
      @stop = false
      Signal.trap("INT") { @stop = true }
      Signal.trap("TERM") { @stop = true }
      @state = State.new(symbols: cfg["SYMBOLS"]&.keys || [], session_target: cfg.dig("global", "min_profit_target").to_f,
                         max_day_loss: cfg.dig("global", "max_day_loss").to_f)
      @virtual_data_manager = VirtualDataManager.new(memory_only: true)

      # Initialize balance provider (always paper for dryrun)
      starting_balance = cfg.dig("paper", "starting_balance") || 200_000.0
      @balance_provider = BalanceProviders::PaperWallet.new(starting_balance: starting_balance)

      # Initialize quantity sizer
      @quantity_sizer = QuantitySizer.new(cfg, @balance_provider)

      # Initialize mock broker for dryrun
      @broker = Brokers::PaperBroker.new(virtual_data_manager: @virtual_data_manager,
                                         balance_provider: @balance_provider)
    end

    def start
      DhanHQ.configure_with_env
      DhanHQ.logger.level = Logger::WARN

      puts "[DRYRUN] Starting signal analysis mode"
      puts "[DRYRUN] No WebSocket connections will be made"
      puts "[DRYRUN] No orders will be placed"
      puts "[DRYRUN] Only signal analysis will be performed"

      # Simple logger removed - using console output instead

      puts "[READY] Symbols: #{@cfg["SYMBOLS"]&.keys&.join(", ") || "None"}"
      puts "[MODE] DRYRUN with balance: ₹#{@balance_provider.available_balance.round(0)}"
      puts "[QUIET] Running in quiet mode - minimal output" if @quiet
      puts "[ONCE] Running analysis once and exiting" if @once
      puts "[CONTROLS] Press Ctrl+C to stop" unless @once

      if @once
        # Single run mode - analyze once and exit
        begin
          analyze_signals
        rescue StandardError => e
          puts "\n[ERR] #{e.class}: #{e.message}"
          puts e.backtrace.first(5).join("\n") if @cfg.dig("global", "log_level") == "DEBUG"
        end
      else
        # Continuous mode - run in loop
        last_decision = Time.at(0)
        last_status_update = Time.at(0)
        decision_interval = @cfg.dig("global", "decision_interval").to_i
        status_interval = 30 # Update status every 30 seconds in quiet mode

        until @stop
          begin
            # pause/resume by state
            if @state.status == :paused
              sleep 0.2
              next
            end

            if Time.now - last_decision >= decision_interval
              last_decision = Time.now
              analyze_signals
            end

            # Periodic status updates in quiet mode
            if @quiet && Time.now - last_status_update >= status_interval
              last_status_update = Time.now
              # Status updates removed - using simple console output instead
            end
          rescue StandardError => e
            puts "\n[ERR] #{e.class}: #{e.message}"
            puts e.backtrace.first(5).join("\n") if @cfg.dig("global", "log_level") == "DEBUG"
          ensure
            sleep 0.5
          end
        end
      end
    ensure
      @state.set_status(:stopped)
      puts "\n[DRYRUN] Signal analysis stopped"
    end

    private

    def analyze_signals
      @cfg["SYMBOLS"]&.each_key do |sym|
        next unless sym

        s = sym_cfg(sym)
        next if s["idx_sid"].to_s.empty?

        puts "\n[#{sym}] Analyzing signals..." unless @quiet

        begin
          # Get current spot price (mock for dryrun)
          spot = get_mock_spot_price(sym)
          puts "[#{sym}] Mock spot price: #{spot}" unless @quiet

          # Get trend direction (reuse cached trend object if available)
          trend_key = "#{sym}_trend"
          if @cached_trends && @cached_trends[trend_key]
            trend = @cached_trends[trend_key]
          else
            if @enhanced
              use_multi_timeframe = @cfg.dig("global", "use_multi_timeframe") != false
              secondary_timeframe = @cfg.dig("global", "secondary_timeframe") || 5
              trend = DhanScalper::TrendEnhanced.new(
                seg_idx: s["seg_idx"],
                sid_idx: s["idx_sid"],
                use_multi_timeframe: use_multi_timeframe,
                secondary_timeframe: secondary_timeframe,
              )
            else
              trend = DhanScalper::Trend.new(seg_idx: s["seg_idx"], sid_idx: s["idx_sid"])
            end

            # Cache the trend object
            @cached_trends ||= {}
            @cached_trends[trend_key] = trend
          end

          direction = trend.decide
          puts "[#{sym}] Signal: #{direction}" unless @quiet

          # Analyze what would happen (reuse cached picker if available)
          analyze_signal_impact(sym, direction, spot, s)
        rescue StandardError => e
          puts "[#{sym}] Error analyzing signals: #{e.message}"
          puts e.backtrace.first(3).join("\n") if @cfg.dig("global", "log_level") == "DEBUG"
        end
      end
    end

    def analyze_signal_impact(symbol, direction, spot, symbol_config)
      return if direction == :none

      # Cache option picker to avoid reloading CSV data repeatedly
      picker_key = "#{symbol}_picker"
      if @cached_pickers && @cached_pickers[picker_key]
        picker = @cached_pickers[picker_key]
      else
        picker = OptionPicker.new(symbol_config, mode: :paper)
        @cached_pickers ||= {}
        @cached_pickers[picker_key] = picker
      end

      pick = picker.pick(current_spot: spot)

      if pick[:ce_sid] && pick[:pe_sid]
        puts "[#{symbol}] Would pick options: CE=#{pick[:ce_sid]}, PE=#{pick[:pe_sid]}" unless @quiet

        # Calculate what quantity would be used
        option_price = 50.0 # Mock option price
        lots = @quantity_sizer.calculate_lots(symbol, option_price, side: "BUY")
        quantity = @quantity_sizer.calculate_quantity(symbol, option_price, side: "BUY")

        puts "[#{symbol}] Would use #{lots} lots (#{quantity} quantity) at ₹#{option_price}" unless @quiet

        # Calculate potential P&L
        if direction == :bullish
          puts "[#{symbol}] Would BUY CE option" unless @quiet
        elsif direction == :bearish
          puts "[#{symbol}] Would BUY PE option" unless @quiet
        end
      else
        puts "[#{symbol}] No valid options found for analysis" unless @quiet
      end
    end

    def get_mock_spot_price(symbol)
      # Return mock spot prices for common symbols
      case symbol.to_s.upcase
      when "NIFTY"
        19_500.0
      when "BANKNIFTY"
        45_000.0
      when "SENSEX"
        65_000.0
      else
        20_000.0
      end
    end

    def sym_cfg(sym) = @cfg.fetch("SYMBOLS").fetch(sym)
  end
end
