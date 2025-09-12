# frozen_string_literal: true

require "logger"
require_relative "state"
require_relative "brokers/base"
require_relative "brokers/paper_broker"
require_relative "balance_providers/paper_wallet"
require_relative "quantity_sizer"
require_relative "trend_enhanced"
require_relative "option_picker"
require_relative "services/websocket_manager"
require_relative "services/paper_position_tracker"
require_relative "exchange_segment_mapper"
require_relative "csv_master"
require_relative "services/session_reporter"

module DhanScalper
  class PaperApp
    def initialize(cfg, quiet: false, enhanced: true, timeout_minutes: nil)
      @cfg = cfg
      @quiet = quiet
      @enhanced = enhanced
      @timeout_minutes = timeout_minutes
      @stop = false
      @start_time = Time.now
      Signal.trap("INT") { @stop = true }
      Signal.trap("TERM") { @stop = true }

      @state = State.new(
        symbols: cfg["SYMBOLS"]&.keys || [],
        session_target: cfg.dig("global", "min_profit_target").to_f,
        max_day_loss: cfg.dig("global", "max_day_loss").to_f,
      )

      @virtual_data_manager = VirtualDataManager.new(memory_only: true)

      # Initialize balance provider
      starting_balance = cfg.dig("paper", "starting_balance") || 200_000.0
      @balance_provider = BalanceProviders::PaperWallet.new(starting_balance: starting_balance)

      # Initialize quantity sizer
      @quantity_sizer = QuantitySizer.new(cfg, @balance_provider)

      # Initialize broker
      @broker = Brokers::PaperBroker.new(
        virtual_data_manager: @virtual_data_manager,
        balance_provider: @balance_provider,
      )

      # Make the broker use the same position tracker as the app
      @broker.instance_variable_set(:@position_tracker, @position_tracker)

      # Initialize WebSocket manager
      @websocket_manager = Services::WebSocketManager.new(logger: @logger)

      # Initialize position tracker
      @position_tracker = Services::PaperPositionTracker.new(
        websocket_manager: @websocket_manager,
        logger: @logger,
        memory_only: true,
      )

      # Initialize logger
      @logger = Logger.new($stdout)
      @logger.level = quiet ? Logger::WARN : Logger::INFO

      # Initialize CSV master for exchange segment mapping
      @csv_master = CsvMaster.new

      # Initialize session reporter
      @session_reporter = Services::SessionReporter.new

      # Session tracking variables
      @session_data = {
        session_id: nil,
        start_time: nil,
        end_time: nil,
        total_trades: 0,
        successful_trades: 0,
        failed_trades: 0,
        trades: [],
        max_pnl: 0.0,
        min_pnl: 0.0,
        symbols_traded: Set.new,
      }

      # Cache for trend objects and option pickers
      @cached_trends = {}
      @cached_pickers = {}

      # Cache for security ID to strike mapping
      @security_to_strike = {}
    end

    def start
      DhanHQ.configure_with_env
      DhanHQ.logger.level = Logger::WARN

      # Initialize session data
      @session_data[:session_id] = "PAPER_#{Time.now.strftime("%Y%m%d_%H%M%S")}"
      @session_data[:start_time] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
      @session_data[:starting_balance] = @balance_provider.available_balance

      puts "[PAPER] Starting paper trading mode"
      puts "[PAPER] Session ID: #{@session_data[:session_id]}"
      puts "[PAPER] WebSocket connection will be established"
      puts "[PAPER] Positions will be tracked in real-time"
      puts "[PAPER] No real money will be used"
      puts "[TIMEOUT] Auto-exit after #{@timeout_minutes} minutes" if @timeout_minutes

      # Simple logging for quiet mode
      @logger = Logger.new($stdout) if @quiet

      puts "[READY] Symbols: #{@cfg["SYMBOLS"]&.keys&.join(", ") || "None"}"
      puts "[MODE] PAPER with balance: ₹#{@balance_provider.available_balance.round(0)}"
      puts "[QUIET] Running in quiet mode - minimal output" if @quiet
      puts "[CONTROLS] Press Ctrl+C to stop"

      begin
        # Configure baseline indices and active instrument provider
        baseline = Array(@cfg["SYMBOLS"]).flat_map do |_sym, s|
          sid = s&.dig("idx_sid")
          sid.to_s.empty? ? [] : [[sid.to_s, "INDEX"]]
        end
        @websocket_manager.set_baseline_instruments(baseline)
        @websocket_manager.set_active_instruments_provider do
          # Any instruments with quantity > 0 in paper tracker
          @position_tracker.positions.values.select do |p|
            (p[:quantity] || 0).to_f > 0
          end.map { |p| [p[:instrument_id].to_s, "OPTION"] }
        end

        # Connect to WebSocket
        @websocket_manager.connect

        # Setup position tracker WebSocket handlers
        @position_tracker.setup_websocket_handlers

        # Setup tick handler to store data in TickCache
        @websocket_manager.on_price_update do |price_data|
          # Use the segment provided by WebSocket manager (it already has the correct segment)
          exchange_segment = price_data[:segment] || "NSE_FNO"

          # Convert price_data to tick format for TickCache
          tick_data = {
            segment: exchange_segment,
            security_id: price_data[:instrument_id], # This is correct - instrument_id contains security_id
            ltp: price_data[:last_price],
            open: price_data[:open],
            high: price_data[:high],
            low: price_data[:low],
            close: price_data[:close],
            volume: price_data[:volume],
            ts: price_data[:timestamp],
          }

          # Debug: Log the tick data being stored
          if ENV["DHAN_LOG_LEVEL"] == "DEBUG"
            puts "[DEBUG] Storing tick data: #{tick_data[:segment]}:#{tick_data[:security_id]} LTP=#{tick_data[:ltp]}"
          end

          DhanScalper::TickCache.put(tick_data)
        end

        # Start tracking underlying instruments
        start_tracking_underlyings

        # Subscribe to ATM options for monitoring (even without trading signals)
        # Wait a bit for spot price to be available
        sleep(2)
        subscribe_to_atm_options_for_monitoring

        # Main trading loop
        last_decision = Time.at(0)
        last_status_update = Time.at(0)
        last_ltp_update = Time.at(0)
        decision_interval = @cfg.dig("global", "decision_interval").to_i
        status_interval = 30

        until @stop
          begin
            # Check timeout
            if @timeout_minutes && (Time.now - @start_time) >= (@timeout_minutes * 60)
              puts "[TIMEOUT] #{@timeout_minutes} minutes elapsed. Auto-exiting..."
              @stop = true
              break
            end

            # Pause/resume by state
            if @state.status == :paused
              sleep 0.2
              next
            end

            # Make trading decisions
            if Time.now - last_decision >= decision_interval
              last_decision = Time.now
              analyze_and_trade
            end

            # Risk management
            check_risk_limits

            # Periodic status updates
            if @quiet && Time.now - last_status_update >= status_interval
              last_status_update = Time.now
              # Status updates removed - using simple console output instead
            end

            # Show position summary periodically
            if Time.now - last_status_update >= 60 # Every minute
              show_position_summary
              if @timeout_minutes
                elapsed = (Time.now - @start_time) / 60
                remaining = @timeout_minutes - elapsed
                puts "[TIMEOUT] #{remaining.round(1)} minutes remaining" if remaining > 0
              end
              last_status_update = Time.now
            end

            # Show LTPs every 30 seconds
            if Time.now - last_ltp_update >= 30 # Every 30 seconds
              print_subscribed_ltps
              last_ltp_update = Time.now
            end
          rescue StandardError => e
            puts "\n[ERR] #{e.class}: #{e.message}"
            puts e.backtrace.first(5).join("\n") if @cfg.dig("global", "log_level") == "DEBUG"
          ensure
            sleep 0.5
          end
        end
      ensure
        @state.set_status(:stopped)
        @websocket_manager.disconnect
        puts "\n[PAPER] Trading stopped"

        # Finalize session data
        @session_data[:end_time] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        @session_data[:duration_minutes] = (Time.now - @start_time) / 60.0
        @session_data[:ending_balance] = @balance_provider.total_balance
        @session_data[:total_pnl] = @session_data[:ending_balance] - @session_data[:starting_balance]
        @session_data[:win_rate] =
          @session_data[:total_trades] > 0 ? (@session_data[:successful_trades].to_f / @session_data[:total_trades] * 100) : 0.0
        @session_data[:average_trade_pnl] =
          @session_data[:total_trades] > 0 ? (@session_data[:total_pnl] / @session_data[:total_trades]) : 0.0

        # Get positions summary
        positions_summary = @position_tracker.get_positions_summary
        @session_data[:positions] = positions_summary[:positions].values
        @session_data[:symbols_traded] = @session_data[:symbols_traded].to_a

        show_final_summary
        @position_tracker.save_session_data

        # Generate comprehensive session report
        generate_session_report
      end
    end

    private

    def determine_option_segment(symbol, option_sid)
      # Use CSV master to get the correct exchange segment
      begin
        segment = @csv_master.get_exchange_segment(option_sid)

        if segment
          puts "[#{symbol}] Found segment #{segment} for option #{option_sid}"
          return segment
        end
      rescue StandardError => e
        puts "[#{symbol}] CSV master lookup failed for #{option_sid}: #{e.message}"
      end

      # Fallback: determine based on underlying symbol
      case symbol.to_s.upcase
      when "SENSEX"
        "BSE_FNO"
      when "NIFTY", "BANKNIFTY"
        "NSE_FNO"
      else
        "NSE_FNO" # Default to NSE
      end
    end

    def start_tracking_underlyings
      @cfg["SYMBOLS"]&.each_key do |sym|
        next unless sym

        s = sym_cfg(sym)
        next if s["idx_sid"].to_s.empty?

        puts "[PAPER] Starting to track underlying: #{sym}"

        # Track the underlying index
        success = @position_tracker.track_underlying(sym, s["idx_sid"])

        if success
          puts "[PAPER] Now tracking #{sym} (#{s["idx_sid"]})"
        else
          puts "[PAPER] Failed to track #{sym}"
        end
      end
    end

    def analyze_and_trade
      @cfg["SYMBOLS"]&.each_key do |sym|
        next unless sym

        s = sym_cfg(sym)
        next if s["idx_sid"].to_s.empty?

        begin
          # Get current spot price from WebSocket
          spot_price = @position_tracker.get_underlying_price(sym)

          if spot_price.nil?
            puts "[#{sym}] No price data available yet, skipping..."
            next
          end

          puts "\n[#{sym}] Analyzing signals at spot: #{spot_price}"

          # Get trend direction
          trend = get_cached_trend(sym, s)
          direction = trend.decide

          puts "[#{sym}] Signal: #{direction}"

          # Execute trades based on signals
          execute_trade(sym, direction, spot_price, s) if direction != :none
        rescue StandardError => e
          puts "[#{sym}] Error in analysis: #{e.message}"
          puts e.backtrace.first(3).join("\n") if @cfg.dig("global", "log_level") == "DEBUG"
        end
      end
    end

    def execute_trade(symbol, direction, spot_price, symbol_config)
      return if direction == :none

      # Get option picker
      picker = get_cached_picker(symbol, symbol_config)
      pick = picker.pick(current_spot: spot_price)

      return unless pick[:ce_sid] && pick[:pe_sid]

      # Calculate the actual strike price (ATM)
      strike_step = symbol_config["strike_step"] || 50
      actual_strike = picker.nearest_strike(spot_price, strike_step)

      # Subscribe to ATM and ATM+/- options for LTP monitoring
      subscribe_to_atm_options(symbol, spot_price, actual_strike, strike_step, pick)

      # Determine which option to trade
      option_sid = case direction
                   when :bullish, :long_ce
                     pick[:ce_sid][actual_strike]
                   when :bearish, :long_pe
                     pick[:pe_sid][actual_strike]
                   else
                     return
                   end

      return unless option_sid

      option_type = case direction
                    when :bullish, :long_ce
                      "CE"
                    when :bearish, :long_pe
                      "PE"
                    end

      # Subscribe to option instrument first
      @websocket_manager.subscribe_to_instrument(option_sid, "OPTION")

      # Wait a moment for subscription to establish
      sleep(0.1)

      # Determine the correct segment for options based on underlying
      option_segment = determine_option_segment(symbol, option_sid)

      # Get real market price for the option
      # puts DhanScalper::TickCache.all
      puts "[#{symbol}] Getting market price for #{option_sid} in #{option_segment}"
      option_price = DhanScalper::TickCache.ltp(option_segment, option_sid)&.to_f

      # Skip trade if no real market price is available
      unless option_price&.positive?
        puts "[#{symbol}] No market price available for #{option_sid}, skipping trade"
        return
      end

      # Calculate position size
      quantity = @quantity_sizer.calculate_quantity(symbol, option_price, side: "BUY")

      puts "[#{symbol}] Executing #{direction} trade: #{option_type} #{quantity} lots at ₹#{option_price} (Strike: #{actual_strike})"

      # Place paper order
      order_result = @broker.place_order(
        symbol: symbol,
        instrument_id: option_sid,
        side: "BUY",
        quantity: quantity,
        price: option_price,
        order_type: "MARKET",
      )

      if order_result[:success]
        puts "[#{symbol}] Order placed successfully: #{order_result[:order_id]}"

        # Add position to tracker
        position_key = "#{symbol}_#{option_type}_#{actual_strike}_#{Date.today}"
        @position_tracker.add_position(
          symbol, option_type, actual_strike, Date.today,
          option_sid, quantity, option_price
        )

        # Track trade in session data
        @session_data[:total_trades] += 1
        @session_data[:successful_trades] += 1
        @session_data[:symbols_traded].add(symbol)
        @session_data[:trades] << {
          timestamp: Time.now.strftime("%H:%M:%S"),
          symbol: symbol,
          side: "BUY",
          quantity: quantity,
          price: option_price,
          order_id: order_result[:order_id],
          status: "SUCCESS",
          option_type: option_type,
          strike: actual_strike,
        }

        puts "[#{symbol}] Position added to tracker: #{position_key}"
      else
        puts "[#{symbol}] Order failed: #{order_result[:error]}"

        # Track failed trade
        @session_data[:total_trades] += 1
        @session_data[:failed_trades] += 1
        @session_data[:trades] << {
          timestamp: Time.now.strftime("%H:%M:%S"),
          symbol: symbol,
          side: "BUY",
          quantity: quantity,
          price: option_price,
          order_id: nil,
          status: "FAILED",
          error: order_result[:error],
          option_type: option_type,
          strike: actual_strike,
        }
      end
    end

    def execute_buy_trade(symbol, direction, spot_price, symbol_config)
      execute_trade(symbol, direction, spot_price, symbol_config)
    end

    def execute_sell_trade(symbol, direction, spot_price, symbol_config)
      # For now, sell trades are handled by the broker's close_matching_position method
      # This is a placeholder for the test structure
      execute_trade(symbol, direction, spot_price, symbol_config)
    end

    def check_risk_limits
      # Check daily loss limit
      total_pnl = @position_tracker.get_total_pnl
      max_loss = @cfg.dig("global", "max_day_loss").to_f

      if total_pnl < -max_loss
        puts "[RISK] Daily loss limit exceeded: ₹#{total_pnl} (limit: ₹#{max_loss})"
        puts "[RISK] Stopping trading for today"
        @stop = true
      end

      # Check position limits
      max_positions = @cfg.dig("global", "max_positions").to_i
      return unless max_positions > 0 && @position_tracker.positions.size >= max_positions

      puts "[RISK] Maximum positions reached: #{@position_tracker.positions.size}"
      puts "[RISK] No new positions will be opened"
    end

    def show_position_summary
      summary = @position_tracker.get_positions_summary
      underlying_summary = @position_tracker.get_underlying_summary

      # Update session P&L tracking
      current_pnl = summary[:total_pnl]
      @session_data[:max_pnl] = [@session_data[:max_pnl], current_pnl].max
      @session_data[:min_pnl] = [@session_data[:min_pnl], current_pnl].min

      puts "\n" + ("=" * 60)
      puts "[POSITION SUMMARY]"
      puts "Total Positions: #{summary[:total_positions]}"
      puts "Total P&L: ₹#{summary[:total_pnl].round(2)}"
      puts "Available Balance: ₹#{@balance_provider.available_balance.round(0)}"
      puts "Session Max P&L: ₹#{@session_data[:max_pnl].round(2)}"
      puts "Session Min P&L: ₹#{@session_data[:min_pnl].round(2)}"

      if underlying_summary.any?
        puts "\n[UNDERLYING PRICES]"
        underlying_summary.each do |symbol, data|
          price = data[:last_price] ? "₹#{data[:last_price]}" : "N/A"
          puts "#{symbol}: #{price} (#{data[:instrument_id]})"
        end
      end

      if summary[:positions].any?
        puts "\n[POSITIONS]"
        summary[:positions].each do |key, pos|
          puts "#{key}: #{pos[:quantity]} #{pos[:option_type]} @ ₹#{pos[:entry_price]} | P&L: ₹#{pos[:pnl].round(2)}"
        end
      end

      puts "=" * 60
    end

    def show_final_summary
      summary = @position_tracker.get_positions_summary

      puts "\n" + ("=" * 60)
      puts "[FINAL SUMMARY]"
      puts "Session P&L: ₹#{summary[:total_pnl].round(2)}"
      puts "Final Balance: ₹#{@balance_provider.available_balance.round(0)}"
      puts "Positions Closed: #{summary[:total_positions]}"
      puts "=" * 60
    end

    def subscribe_to_atm_options_for_monitoring
      puts "\n[ATM MONITOR] Setting up ATM options subscription for monitoring..."

      @cfg["SYMBOLS"]&.each_key do |symbol|
        next unless symbol

        symbol_config = sym_cfg(symbol)
        next if symbol_config["idx_sid"].to_s.empty?

        # Try to get spot price with retries
        spot_price = nil
        5.times do |attempt|
          # Debug: Show what's in TickCache
          if attempt == 0
            cache_data = DhanScalper::TickCache.all
            puts "[ATM MONITOR] TickCache contents: #{cache_data.keys}"
          end

          # Use IDX_I segment for underlying indices
          underlying_segment = "IDX_I"
          spot_price = DhanScalper::TickCache.ltp(underlying_segment, symbol_config["idx_sid"])&.to_f
          puts "[ATM MONITOR] #{symbol} spot price attempt #{attempt + 1}: #{spot_price}"
          break if spot_price&.positive?

          sleep(1) if attempt < 4
        end

        next unless spot_price&.positive?

        # Get option picker and pick options
        picker = get_cached_picker(symbol, symbol_config)
        pick = picker.pick(current_spot: spot_price)
        next unless pick[:ce_sid] && pick[:pe_sid]

        # Calculate ATM strike
        strike_step = symbol_config["strike_step"] || 50
        atm_strike = picker.nearest_strike(spot_price, strike_step)

        # Subscribe to ATM options
        subscribe_to_atm_options(symbol, spot_price, atm_strike, strike_step, pick)
      end
    end

    def subscribe_to_atm_options(symbol, spot_price, atm_strike, strike_step, pick)
      # Subscribe to ATM, ATM+1, ATM-1 strikes for both CE and PE
      strikes_to_subscribe = [
        atm_strike - strike_step,  # ATM-1
        atm_strike,                # ATM
        atm_strike + strike_step, # ATM+1
      ]

      puts "\n[#{symbol}] Subscribing to ATM options around #{atm_strike}:"

      strikes_to_subscribe.each do |strike|
        # Subscribe to CE
        if pick[:ce_sid][strike]
          security_id = pick[:ce_sid][strike]
          @websocket_manager.subscribe_to_instrument(security_id, "OPTION")
          @security_to_strike[security_id] = { strike: strike, type: "CE", symbol: symbol }
          puts "  ✅ Subscribed to #{strike} CE (#{security_id})"
        end

        # Subscribe to PE
        next unless pick[:pe_sid][strike]

        security_id = pick[:pe_sid][strike]
        @websocket_manager.subscribe_to_instrument(security_id, "OPTION")
        @security_to_strike[security_id] = { strike: strike, type: "PE", symbol: symbol }
        puts "  ✅ Subscribed to #{strike} PE (#{security_id})"
      end

      puts "  📊 Spot: ₹#{spot_price.round(2)} | ATM: #{atm_strike}"
    end

    def print_subscribed_ltps
      puts "\n" + ("=" * 60)
      puts "[LTP MONITOR] - #{Time.now.strftime("%H:%M:%S")}"
      puts "=" * 60

      cache_data = DhanScalper::TickCache.all

      if cache_data && !cache_data.empty?
        puts "\n📊 SUBSCRIBED INSTRUMENTS:"

        # Group by instrument type for better display
        index_instruments = {}
        option_instruments = {}

        cache_data.each do |key, tick|
          if key.include?("IDX_I")
            index_instruments[key] = tick
          else
            option_instruments[key] = tick
          end
        end

        # Display index instruments
        if index_instruments.any?
          puts "\n  📈 INDEX INSTRUMENTS:"
          index_instruments.each do |key, tick|
            ltp = tick[:ltp]
            timestamp = tick[:timestamp]
            age = timestamp ? (Time.now - timestamp).round(1) : "N/A"
            display_key = key.gsub(":", " - ")
            puts "    #{display_key}: LTP=₹#{ltp || "N/A"} (#{age}s ago)"
          end
        end

        # Display option instruments grouped by strike
        if option_instruments.any?
          puts "\n  📊 OPTION INSTRUMENTS:"

          # Group options by strike for better display
          options_by_strike = {}
          option_instruments.each do |key, tick|
            # Extract security ID from key (format: "NSE_FNO:40583")
            security_id = key.split(":").last
            strike_info = @security_to_strike[security_id]

            if strike_info
              strike = strike_info[:strike]
              type = strike_info[:type]
              options_by_strike[strike] ||= {}
              options_by_strike[strike][type] = { tick: tick, security_id: security_id }
            else
              # Fallback for unknown security IDs
              options_by_strike["Unknown"] ||= {}
              options_by_strike["Unknown"][key] = { tick: tick, security_id: security_id }
            end
          end

          # Display options grouped by strike
          options_by_strike.sort_by { |strike, _| strike.to_s }.each do |strike, types|
            puts "\n    Strike #{strike}:"
            types.each do |type, data|
              tick = data[:tick]
              security_id = data[:security_id]
              ltp = tick[:ltp]
              timestamp = tick[:timestamp]
              age = timestamp ? (Time.now - timestamp).round(1) : "N/A"
              puts "      #{type}: LTP=₹#{ltp || "N/A"} (#{age}s ago) [#{security_id}]"
            end
          end
        end
      else
        puts "❌ No instruments subscribed or no data available"
      end

      puts "=" * 60
    end

    def get_cached_trend(symbol, symbol_config)
      trend_key = "#{symbol}_trend"

      unless @cached_trends[trend_key]
        if @enhanced
          use_multi_timeframe = @cfg.dig("global", "use_multi_timeframe") != false
          secondary_timeframe = @cfg.dig("global", "secondary_timeframe") || 5
          @cached_trends[trend_key] = TrendEnhanced.new(
            seg_idx: symbol_config["seg_idx"],
            sid_idx: symbol_config["idx_sid"],
            use_multi_timeframe: use_multi_timeframe,
            secondary_timeframe: secondary_timeframe,
          )
        else
          @cached_trends[trend_key] = Trend.new(
            seg_idx: symbol_config["seg_idx"],
            sid_idx: symbol_config["idx_sid"],
          )
        end
      end

      @cached_trends[trend_key]
    end

    def get_cached_picker(symbol, symbol_config)
      picker_key = "#{symbol}_picker"

      unless @cached_pickers[picker_key]
        @cached_pickers[picker_key] =
          OptionPicker.new(symbol_config, mode: :paper, csv_master: @csv_master)
      end

      @cached_pickers[picker_key]
    end

    def sym_cfg(sym)
      @cfg["SYMBOLS"][sym] || {}
    end

    def generate_session_report
      puts "\n[REPORT] Generating comprehensive session report..."

      # Add risk metrics
      @session_data[:risk_metrics] = {
        max_drawdown: @session_data[:min_pnl] || 0.0,
        max_profit: @session_data[:max_pnl] || 0.0,
        risk_reward_ratio: if @session_data[:max_pnl] && @session_data[:max_pnl] > 0 && @session_data[:min_pnl] && @session_data[:min_pnl] < 0
                             (@session_data[:max_pnl] / @session_data[:min_pnl].abs).round(2)
                           else
                             0.0
                           end,
      }

      # Generate the report
      report_result = @session_reporter.generate_session_report(@session_data)

      if report_result
        puts "\n[REPORT] Session report generated successfully!"
        puts "[REPORT] Session ID: #{report_result[:session_id]}"
        puts "[REPORT] JSON Report: #{report_result[:json_file]}"
        puts "[REPORT] CSV Report: #{report_result[:csv_file]}"
      else
        puts "\n[REPORT] Failed to generate session report"
      end
    end
  end
end
