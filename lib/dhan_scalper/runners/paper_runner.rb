# frozen_string_literal: true

require 'DhanHQ'
require 'json'
require 'fileutils'
require_relative 'base_runner'
require_relative '../services/websocket_manager'
require_relative '../services/paper_position_tracker'
require_relative '../services/session_reporter'
require_relative '../services/session_manager'
require_relative '../services/trading_executor'

module DhanScalper
  module Runners
    # Paper trading runner
    class PaperRunner < BaseRunner
      def initialize(config, quiet: false, enhanced: true, timeout_minutes: nil)
        super(config, mode: :paper, quiet: quiet, enhanced: enhanced)

        @timeout_minutes = timeout_minutes
        @start_time = Time.now

        # Initialize virtual data manager
        initialize_virtual_data_manager

        # Initialize logger
        @logger = Logger.new($stdout)
        @logger.level = quiet ? Logger::WARN : Logger::INFO

        # Initialize CSV master for exchange segment mapping
        @csv_master = CsvMaster.new

        # Initialize Redis store
        @redis_store = DhanScalper::Stores::RedisStore.new
        @redis_store.connect

        # Initialize session reporter with config
        @session_reporter = Services::SessionReporter.new(config: @config, logger: @logger, redis_store: @redis_store)

        # Initialize session manager
        @session_manager = Services::SessionManager.new(
          session_reporter: @session_reporter,
          logger: @logger
        )

        # Initialize caches
        @cached_trends = {}
        @cached_pickers = {}
        @security_to_strike = {}
      end

      def start
        DhanHQ.configure_with_env
        DhanHQ.logger.level = Logger::WARN

        # Load or create session data for the current trading day
        @session_manager.load_or_create_session(
          mode: 'PAPER',
          starting_balance: @balance_provider.available_balance
        )

        # Initialize session data
        @session_data = @session_manager.session_data || {}

        # Initialize WebSocket manager
        @websocket_manager = Services::WebSocketManager.new(logger: @logger)

        # Initialize position tracker with Redis
        @position_tracker = Services::PaperPositionTracker.new(
          websocket_manager: @websocket_manager,
          logger: @logger,
          memory_only: true,
          session_id: @session_manager.session_data[:session_id],
          redis_store: @redis_store
        )

        # Update balance provider with position tracker for accurate used balance calculation
        @balance_provider.instance_variable_set(:@position_tracker, @position_tracker)

        # Initialize equity calculator for risk management
        log_throttle = @config.dig('global', 'log_throttle_sec')
        log_throttle = nil unless log_throttle.is_a?(Numeric) && log_throttle.positive?
        @equity_calculator = Services::EquityCalculator.new(
          position_tracker: @position_tracker,
          balance_provider: @balance_provider,
          logger: @logger,
          log_throttle_sec: log_throttle
        )

        # Initialize trading executor
        @trading_executor = Services::TradingExecutor.new(
          broker: @broker,
          position_tracker: @position_tracker,
          balance_provider: @balance_provider,
          session_manager: @session_manager,
          logger: @logger
        )

        # If resuming an existing session, update the balance provider to reflect the correct state
        if @session_manager.session_data[:starting_balance] && @session_manager.session_data[:starting_balance] != @balance_provider.available_balance
          puts '[PAPER] Resuming existing session - updating balance provider'
          puts "[PAPER] Session starting balance: ₹#{@session_manager.session_data[:starting_balance]}"
          puts "[PAPER] Current balance provider: ₹#{@balance_provider.available_balance}"

          # Reset the balance provider to match the session's starting balance
          @balance_provider.reset_balance(@session_manager.session_data[:starting_balance])

          # Update the balance provider with the correct used balance from positions
          if @session_manager.session_data[:positions]&.any?
            used_balance = calculate_used_balance_from_positions(@session_manager.session_data[:positions])
            @balance_provider.instance_variable_set(:@used, DhanScalper::Support::Money.bd(used_balance))
            @balance_provider.instance_variable_set(:@available,
                                                    DhanScalper::Support::Money.bd(@session_manager.session_data[:starting_balance] - used_balance))
            @balance_provider.instance_variable_set(:@total, DhanScalper::Support::Money.bd(@session_manager.session_data[:starting_balance]))

            puts "[PAPER] Updated balance - Available: ₹#{@balance_provider.available_balance}, Used: ₹#{@balance_provider.used_balance}"
          end
        end

        puts '[PAPER] Starting paper trading mode'
        puts "[PAPER] Session ID: #{@session_manager.session_data[:session_id]}"
        puts '[PAPER] WebSocket connection will be established'
        puts '[PAPER] Positions will be tracked in real-time'
        puts '[PAPER] No real money will be used'
        puts "[TIMEOUT] Auto-exit after #{@timeout_minutes} minutes" if @timeout_minutes

        # Simple logging for quiet mode
        @logger = Logger.new($stdout) if @quiet

        display_startup_info

        begin
          setup_websocket_connection
          start_tracking_underlyings
          load_existing_positions
          subscribe_to_atm_options_for_monitoring
          run_main_loop
        ensure
          cleanup
          generate_session_report
        end
      end

      protected

      def get_total_pnl
        @position_tracker.get_total_pnl
      end

      def no_open_positions?
        @position_tracker.positions.empty?
      end

      private

      def setup_websocket_connection
        # Configure baseline indices and active instrument provider
        baseline = Array(@config['SYMBOLS']).flat_map do |_sym, s|
          sid = s&.dig('idx_sid')
          sid.to_s.empty? ? [] : [[sid.to_s, 'INDEX']]
        end
        @websocket_manager.set_baseline_instruments(baseline)
        @websocket_manager.set_active_instruments_provider do
          # Any instruments with quantity > 0 in paper tracker
          @position_tracker.positions.values.select do |p|
            (p[:quantity] || 0).to_f.positive?
          end.map { |p| [p[:instrument_id].to_s, 'OPTION'] }
        end

        # Connect to WebSocket
        @websocket_manager.connect

        # Setup position tracker WebSocket handlers
        @position_tracker.setup_websocket_handlers

        # Setup tick handler to store data in TickCache
        @websocket_manager.on_price_update do |price_data|
          # Use the segment provided by WebSocket manager (it already has the correct segment)
          exchange_segment = price_data[:segment] || 'NSE_FNO'

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
            ts: price_data[:timestamp]
          }

          # Debug: Log the tick data being stored
          if ENV['DHAN_LOG_LEVEL'] == 'DEBUG'
            puts "[DEBUG] Storing tick data: #{tick_data[:segment]}:#{tick_data[:security_id]} LTP=#{tick_data[:ltp]}"
          end

          DhanScalper::TickCache.put(tick_data)

          # Update positions with live data for risk management
          refresh_positions_with_live_data
        end
      end

      def start_tracking_underlyings
        @config['SYMBOLS']&.each_key do |sym|
          next unless sym

          s = sym_cfg(sym)
          next if s['idx_sid'].to_s.empty?

          puts "[PAPER] Starting to track underlying: #{sym}"

          # Track the underlying index
          success = @position_tracker.track_underlying(sym, s['idx_sid'])

          if success
            puts "[PAPER] Now tracking #{sym} (#{s['idx_sid']})"
          else
            puts "[PAPER] Failed to track #{sym}"
          end
        end
      end

      def load_existing_positions
        return unless @session_manager.session_data && @session_manager.session_data[:positions]

        existing_positions = @session_manager.session_data[:positions]
        return if existing_positions.empty?

        puts "\n[POSITION LOADER] Loading #{existing_positions.size} existing positions from session data..."

        existing_positions.each do |position_data|
          symbol = position_data[:symbol]
          option_type = position_data[:option_type]
          strike = position_data[:strike]
          quantity = position_data[:quantity]
          entry_price = position_data[:entry_price]
          position_data[:created_at]

          # Skip if position is closed (quantity is 0 or negative)
          next if quantity.to_i <= 0

          # Find the security ID for this option
          symbol_config = sym_cfg(symbol)
          next if symbol_config.empty?

          # Get option picker to find the security ID
          picker = get_cached_picker(symbol, symbol_config)

          # Get current spot price to determine ATM
          spot_price = @position_tracker.get_underlying_price(symbol)
          next unless spot_price&.positive?

          # Calculate ATM strike
          strike_step = symbol_config['strike_step'] || 50
          picker.nearest_strike(spot_price, strike_step)

          # Find the security ID for this strike and option type
          pick = picker.pick(current_spot: spot_price)
          security_id = case option_type
                        when 'CE'
                          pick[:ce_sid][strike]
                        when 'PE'
                          pick[:pe_sid][strike]
                        end

          next unless security_id

          # Subscribe to the option instrument
          @websocket_manager.subscribe_to_instrument(security_id, 'OPTION')

          # Add position to tracker
          @position_tracker.add_position(
            symbol: symbol,
            option_type: option_type,
            strike: strike,
            expiry: Date.today,
            instrument_id: security_id,
            quantity: quantity,
            entry_price: entry_price
          )

          # Store security ID to strike mapping for display
          @security_to_strike[security_id] = {
            strike: strike,
            type: option_type,
            symbol: symbol
          }

          puts "  ✅ Loaded position: #{symbol} #{option_type} #{strike} (#{quantity} lots @ ₹#{entry_price}) [#{security_id}]"
        rescue StandardError => e
          puts "  ❌ Failed to load position #{position_data[:symbol]}: #{e.message}"
          puts "    Error details: #{e.backtrace.first(2).join("\n")}" if @config.dig('global',
                                                                                      'log_level') == 'DEBUG'
        end

        puts '[POSITION LOADER] Position loading complete'
      end

      def subscribe_to_atm_options_for_monitoring
        puts "\n[ATM MONITOR] Setting up ATM options subscription for monitoring..."

        @config['SYMBOLS']&.each_key do |symbol|
          next unless symbol

          symbol_config = sym_cfg(symbol)
          next if symbol_config['idx_sid'].to_s.empty?

          # Try to get spot price with retries
          spot_price = nil
          5.times do |attempt|
            # Debug: Show what's in TickCache
            if attempt.zero?
              cache_data = DhanScalper::TickCache.all
              puts "[ATM MONITOR] TickCache contents: #{cache_data.keys}"
            end

            # Use IDX_I segment for underlying indices
            underlying_segment = 'IDX_I'
            spot_price = DhanScalper::TickCache.ltp(underlying_segment, symbol_config['idx_sid'])&.to_f
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
          strike_step = symbol_config['strike_step'] || 50
          atm_strike = picker.nearest_strike(spot_price, strike_step)

          # Subscribe to ATM options
          subscribe_to_atm_options(symbol, spot_price, atm_strike, strike_step, pick)
        end
      end

      def run_main_loop
        last_decision = Time.at(0)
        last_status_update = Time.at(0)
        last_ltp_update = Time.at(0)
        decision_interval = get_decision_interval
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
                puts "[TIMEOUT] #{remaining.round(1)} minutes remaining" if remaining.positive?
              end
              last_status_update = Time.now
            end

            # Show LTPs every 30 seconds
            if Time.now - last_ltp_update >= 30 # Every 30 seconds
              print_subscribed_ltps
              last_ltp_update = Time.now
            end
          rescue StandardError => e
            log_error(e)
          ensure
            sleep 0.5
          end
        end
      end

      def analyze_and_trade
        @config['SYMBOLS']&.each_key do |symbol|
          next unless symbol

          symbol_config = sym_cfg(symbol)
          next if symbol_config['idx_sid'].to_s.empty?

          begin
            # Get current spot price from WebSocket
            spot_price = @position_tracker.get_underlying_price(symbol)

            if spot_price.nil?
              puts "[#{symbol}] No price data available yet, skipping..."
              next
            end

            puts "\n[#{symbol}] Analyzing signals at spot: #{spot_price}"

            # Get trend direction
            trend = get_cached_trend(symbol, symbol_config)
            direction = trend.decide

            puts "[#{symbol}] Signal: #{direction}"

            # Generate pick data for trading
            if direction != :none
              picker = get_cached_picker(symbol, symbol_config)
              pick = picker.pick(current_spot: spot_price)

              if pick[:ce_sid] && pick[:pe_sid]
                # Execute trades based on signals
                @trading_executor.execute_trade(symbol, symbol_config, direction, spot_price, pick)
              else
                puts "[#{symbol}] No valid options available for trading"
              end
            end
          rescue StandardError => e
            puts "[#{symbol}] Error in analysis: #{e.message}"
            puts e.backtrace.first(3).join("\n") if @config.dig('global', 'log_level') == 'DEBUG'
          end
        end
      end

      # Removed execute_trade_old method - functionality moved to TradingExecutor
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
        when 'SENSEX'
          'BSE_FNO'
        when 'NIFTY', 'BANKNIFTY'
          'NSE_FNO'
        else
          'NSE_FNO' # Default to NSE
        end
      end

      def subscribe_to_atm_options(symbol, spot_price, atm_strike, strike_step, pick)
        # Subscribe to ATM, ATM+1, ATM-1 strikes for both CE and PE
        strikes_to_subscribe = [
          atm_strike - strike_step,  # ATM-1
          atm_strike,                # ATM
          atm_strike + strike_step # ATM+1
        ]

        puts "\n[#{symbol}] Subscribing to ATM options around #{atm_strike}:"

        strikes_to_subscribe.each do |strike|
          # Subscribe to CE
          if pick[:ce_sid][strike]
            security_id = pick[:ce_sid][strike]
            @websocket_manager.subscribe_to_instrument(security_id, 'OPTION')
            @security_to_strike[security_id] = { strike: strike, type: 'CE', symbol: symbol }
            puts "  ✅ Subscribed to #{strike} CE (#{security_id})"
          end

          # Subscribe to PE
          next unless pick[:pe_sid][strike]

          security_id = pick[:pe_sid][strike]
          @websocket_manager.subscribe_to_instrument(security_id, 'OPTION')
          @security_to_strike[security_id] = { strike: strike, type: 'PE', symbol: symbol }
          puts "  ✅ Subscribed to #{strike} PE (#{security_id})"
        end

        puts "  📊 Spot: ₹#{spot_price.round(2)} | ATM: #{atm_strike}"
      end

      def print_subscribed_ltps
        puts "\n#{'=' * 60}"
        puts "[LTP MONITOR] - #{Time.now.strftime('%H:%M:%S')}"
        puts '=' * 60

        cache_data = DhanScalper::TickCache.all

        puts "Cache data: #{cache_data.inspect}"
        if cache_data && !cache_data.empty?
          puts "\n📊 SUBSCRIBED INSTRUMENTS:"

          # Group by instrument type for better display
          index_instruments = {}
          option_instruments = {}

          cache_data.each do |key, tick|
            if key.include?('IDX_I')
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
              age = timestamp ? (Time.now - timestamp).round(1) : 'N/A'
              display_key = key.gsub(':', ' - ')
              puts "    #{display_key}: LTP=₹#{ltp || 'N/A'} (#{age}s ago)"
            end
          end

          # Display option instruments grouped by strike
          if option_instruments.any?
            puts "\n  📊 OPTION INSTRUMENTS:"

            # Group options by strike for better display
            options_by_strike = {}
            option_instruments.each do |key, tick|
              # Extract security ID from key (format: "NSE_FNO:40583")
              security_id = key.split(':').last
              strike_info = @security_to_strike[security_id]

              if strike_info
                strike = strike_info[:strike]
                type = strike_info[:type]
                options_by_strike[strike] ||= {}
                options_by_strike[strike][type] = { tick: tick, security_id: security_id }
              else
                # Fallback for unknown security IDs
                options_by_strike['Unknown'] ||= {}
                options_by_strike['Unknown'][key] = { tick: tick, security_id: security_id }
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
                age = timestamp ? (Time.now - timestamp).round(1) : 'N/A'
                puts "      #{type}: LTP=₹#{ltp || 'N/A'} (#{age}s ago) [#{security_id}]"
              end
            end
          end
        else
          puts '❌ No instruments subscribed or no data available'
        end

        puts '=' * 60
      end

      def show_position_summary
        summary = @position_tracker.get_positions_summary
        underlying_summary = @position_tracker.get_underlying_summary

        # Update session P&L tracking
        current_pnl = summary[:total_pnl]
        @session_data[:max_pnl] = [@session_data[:max_pnl] || 0.0, current_pnl].max
        @session_data[:min_pnl] = [@session_data[:min_pnl] || 0.0, current_pnl].min

        puts "\n#{'=' * 60}"
        puts '[POSITION SUMMARY]'
        puts "Total Positions: #{summary[:total_positions]}"
        puts "Total P&L: ₹#{summary[:total_pnl].round(2)}"
        puts "Available Balance: ₹#{@balance_provider.available_balance.round(0)}"
        puts "Session Max P&L: ₹#{@session_data[:max_pnl].round(2)}"
        puts "Session Min P&L: ₹#{@session_data[:min_pnl].round(2)}"

        if underlying_summary.any?
          puts "\n[UNDERLYING PRICES]"
          underlying_summary.each do |symbol, data|
            price = data[:last_price] ? "₹#{data[:last_price]}" : 'N/A'
            puts "#{symbol}: #{price} (#{data[:instrument_id]})"
          end
        end

        if summary[:positions].any?
          puts "\n[POSITIONS]"
          summary[:positions].each do |key, pos|
            puts "#{key}: #{pos[:quantity]} #{pos[:option_type]} @ ₹#{pos[:entry_price]} | P&L: ₹#{pos[:pnl].round(2)}"
          end
        end

        puts '=' * 60
      end

      def get_cached_trend(symbol, symbol_config)
        trend_key = "#{symbol}_trend"

        unless @cached_trends[trend_key]
          if @enhanced
            use_multi_timeframe = @config.dig('global', 'use_multi_timeframe') != false
            secondary_timeframe = @config.dig('global', 'secondary_timeframe') || 5
            @cached_trends[trend_key] = TrendEnhanced.new(
              seg_idx: symbol_config['seg_idx'],
              sid_idx: symbol_config['idx_sid'],
              use_multi_timeframe: use_multi_timeframe,
              secondary_timeframe: secondary_timeframe
            )
          else
            @cached_trends[trend_key] = Trend.new(
              seg_idx: symbol_config['seg_idx'],
              sid_idx: symbol_config['idx_sid']
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

      def generate_session_report
        puts "\n[REPORT] Generating comprehensive session report..."

        # Finalize session data
        @session_data = @session_reporter.finalize_session(@session_data)

        # Update session data with current state
        update_session_balance_data
        calculate_session_metrics
        update_positions_data
        add_risk_metrics

        # Generate the report
        generate_final_report
      end

      def update_session_balance_data
        available_balance = @balance_provider.available_balance
        @session_data[:available_balance] = available_balance
        @session_data[:used_balance] = @balance_provider.used_balance
        @session_data[:total_balance] = @balance_provider.total_balance
        @session_data[:ending_balance] = available_balance
      end

      def calculate_session_metrics
        @session_data[:total_pnl] = @session_data[:total_balance] - @session_data[:starting_balance]
        @session_data[:win_rate] =
          @session_data[:total_trades].positive? ? (@session_data[:successful_trades].to_f / @session_data[:total_trades] * 100) : 0.0
        @session_data[:average_trade_pnl] =
          @session_data[:total_trades].positive? ? (@session_data[:total_pnl] / @session_data[:total_trades]) : 0.0
      end

      def update_positions_data
        positions_summary = @position_tracker.get_positions_summary
        @session_data[:positions] = positions_summary[:positions].values
        @session_data[:symbols_traded] =
          @session_data[:symbols_traded].is_a?(Set) ? @session_data[:symbols_traded].to_a : @session_data[:symbols_traded]
      end

      def add_risk_metrics
        max_pnl = @session_data[:max_pnl] || 0.0
        min_pnl = @session_data[:min_pnl] || 0.0
        @session_data[:risk_metrics] = {
          max_drawdown: min_pnl,
          max_profit: max_pnl,
          risk_reward_ratio: if max_pnl.positive? && min_pnl.negative?
                               (max_pnl / min_pnl.abs).round(2)
                             else
                               0.0
                             end
        }
      end

      def generate_final_report
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

      def cleanup
        super
        @websocket_manager.disconnect
        @position_tracker.save_session_data
      end

      def calculate_used_balance_from_positions(positions)
        return 0.0 if positions.nil? || positions.empty?

        # Calculate position values
        position_values = positions.sum do |position|
          quantity = position[:quantity] || position['quantity'] || 0
          entry_price = position[:entry_price] || position['entry_price'] || 0
          quantity * entry_price
        end

        # Calculate total fees (₹20 per order)
        fee_per_order = @config.dig('global', 'charge_per_order') || 20.0
        total_fees = positions.length * fee_per_order

        total_used = position_values + total_fees

        DhanScalper::Support::Logger.debug(
          "Calculated used balance from positions - positions: #{position_values}, fees: #{total_fees}, total: #{total_used}",
          component: 'PaperRunner'
        )

        total_used.to_f
      end

      def refresh_positions_with_live_data
        return unless @equity_calculator

        # Create LTP provider that gets data from TickCache
        ltp_provider = lambda do |exchange_segment, security_id|
          DhanScalper::TickCache.ltp(exchange_segment, security_id)
        end

        # Refresh all positions with live data
        result = @equity_calculator.refresh_all_unrealized!(ltp_provider: ltp_provider)

        if result[:success]
          DhanScalper::Support::Logger.debug(
            "Updated positions with live data - Total unrealized PnL: ₹#{result[:total_unrealized]}",
            component: 'PaperRunner'
          )
        else
          DhanScalper::Support::Logger.warn(
            "Failed to refresh positions with live data: #{result[:error]}",
            component: 'PaperRunner'
          )
        end
      end

      def update_session_data_with_current_state
        # Update session data with current balance and positions
        @session_data[:available_balance] = @balance_provider.available_balance
        @session_data[:used_balance] = @balance_provider.used_balance
        @session_data[:total_balance] = @balance_provider.total_balance

        # Update positions from position tracker
        positions_summary = @position_tracker.get_positions_summary
        @session_data[:positions] = positions_summary[:positions].values

        # Save session data to file for real-time access
        save_session_data_to_file
      end

      def save_session_data_to_file
        # Save current session data to JSON file for real-time access
        session_file = File.join('data/reports', "#{@session_data[:session_id]}.json")

        # Ensure directory exists
        FileUtils.mkdir_p(File.dirname(session_file))

        # Convert Set to Array for JSON serialization
        session_data_for_save = @session_data.dup
        session_data_for_save[:symbols_traded] = if session_data_for_save[:symbols_traded].is_a?(Set)
                                                   session_data_for_save[:symbols_traded].to_a
                                                 else
                                                   session_data_for_save[:symbols_traded]
                                                 end

        File.write(session_file, JSON.pretty_generate(session_data_for_save))

        DhanScalper::Support::Logger.debug(
          "Session data saved to #{session_file}",
          component: 'PaperRunner'
        )
      rescue StandardError => e
        DhanScalper::Support::Logger.debug(
          "Failed to save session data: #{e.message}",
          component: 'PaperRunner'
        )
      end
    end
  end
end
