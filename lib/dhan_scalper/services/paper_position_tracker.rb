# frozen_string_literal: true

require "json"
require "fileutils"

module DhanScalper
  module Services
    class PaperPositionTracker
      attr_reader :positions, :underlying_prices, :websocket_manager

      def initialize(websocket_manager:, logger: nil, memory_only: true)
        @websocket_manager = websocket_manager
        @logger = logger || Logger.new($stdout)
        @memory_only = memory_only
        @positions = {}
        @underlying_prices = {}
        @position_file = "data/paper_positions.json"
        @price_file = "data/underlying_prices.json"

        # Load existing positions and prices only if not memory-only
        load_positions unless @memory_only
        load_underlying_prices unless @memory_only

        # Setup WebSocket handlers
        setup_websocket_handlers
      end

      def track_underlying(symbol, instrument_id)
        @logger.info "[PositionTracker] Starting to track underlying: #{symbol} (#{instrument_id})"

        # Subscribe to underlying price updates
        success = @websocket_manager&.subscribe_to_instrument(instrument_id, "INDEX") || true

        if success
          @underlying_prices[symbol] = {
            instrument_id: instrument_id,
            last_price: nil,
            last_update: nil,
            subscribed: true,
          }
          save_underlying_prices unless @memory_only
          @logger.info "[PositionTracker] Now tracking #{symbol} at #{instrument_id}"
        else
          @logger.error "[PositionTracker] Failed to subscribe to #{symbol}"
        end

        success
      end

      def add_position(symbol, option_type, strike, expiry, instrument_id, quantity, entry_price)
        # Use a simplified key that aggregates by symbol and option type
        position_key = "#{symbol}_#{option_type}"

        @logger.info "[PositionTracker] Adding position: #{position_key} (#{instrument_id})"

        # Subscribe to option price updates (allow failure for testing)
        success = @websocket_manager&.subscribe_to_instrument(instrument_id, "OPTION") || true

        # Always add position even if WebSocket subscription fails (for testing)
        if @positions[position_key]
          # Aggregate with existing position
          existing = @positions[position_key]
          total_quantity = existing[:quantity] + quantity
          # Calculate weighted average entry price
          total_value = (existing[:entry_price] * existing[:quantity]) + (entry_price * quantity)
          weighted_avg_price = total_value / total_quantity

          @positions[position_key] = {
            symbol: symbol,
            option_type: option_type, # CE or PE
            strike: strike.to_i, # Use the latest strike
            expiry: expiry, # Use the latest expiry
            instrument_id: instrument_id, # Use the latest instrument_id
            quantity: total_quantity,
            entry_price: weighted_avg_price,
            current_price: entry_price, # Use current market price
            pnl: 0.0, # Will be calculated later
            created_at: existing[:created_at], # Keep original creation time
            last_update: Time.now,
            subscribed: true,
          }

          @logger.info "[PositionTracker] Position aggregated: #{position_key} (total qty: #{total_quantity})"
        else
          # Create new position
          @positions[position_key] = {
            symbol: symbol,
            option_type: option_type, # CE or PE
            strike: strike.to_i,
            expiry: expiry,
            instrument_id: instrument_id,
            quantity: quantity,
            entry_price: entry_price,
            current_price: entry_price,
            pnl: 0.0,
            created_at: Time.now,
            last_update: Time.now,
            subscribed: true,
          }

          @logger.info "[PositionTracker] Position created: #{position_key}"
        end

        save_positions

        success
      end

      def remove_position(position_key)
        return false unless @positions[position_key]

        position = @positions[position_key]
        @logger.info "[PositionTracker] Removing position: #{position_key}"

        # Unsubscribe from option price updates
        @websocket_manager.unsubscribe_from_instrument(position[:instrument_id])

        # Remove position
        @positions.delete(position_key)
        save_positions

        @logger.info "[PositionTracker] Position removed: #{position_key}"
        true
      end

      def get_underlying_price(symbol)
        # First try position tracker's internal cache
        if @underlying_prices[symbol] && @underlying_prices[symbol][:last_price]
          return @underlying_prices[symbol][:last_price]
        end

        # Fallback to TickCache with LTP fallback for real-time data
        if @underlying_prices[symbol] && @underlying_prices[symbol][:instrument_id]
          instrument_id = @underlying_prices[symbol][:instrument_id]
          segment = @underlying_prices[symbol][:segment] || "IDX_I"

          # Use TickCache with fallback to get live data
          ltp = DhanScalper::TickCache.ltp(segment, instrument_id, use_fallback: true)
          return ltp if ltp
        end

        nil
      end

      def get_position_pnl(position_key)
        return nil unless @positions[position_key]

        position = @positions[position_key]
        current_price = position[:current_price]
        entry_price = position[:entry_price]
        quantity = position[:quantity]

        # Calculate P&L (for options, profit when current > entry for long positions)
        pnl = (current_price - entry_price) * quantity
        position[:pnl] = pnl

        pnl
      end

      def get_total_pnl
        total_pnl = 0.0
        @positions.each_key do |position_key|
          pnl = get_position_pnl(position_key)
          total_pnl += pnl if pnl
        end
        total_pnl
      end

      def get_positions
        @positions.values
      end

      # Method to manually update position prices for testing/debugging
      def update_position_prices
        @logger.debug "[PositionTracker] update_position_prices called - checking #{@positions.size} positions"

        updated_count = 0
        @positions.each do |key, position|
          # Simulate some price movement for testing
          next unless position[:current_price] == position[:entry_price]

          # Add some random price movement (±2-8% change)
          price_change_percent = (rand - 0.5) * 0.12 # ±6% change
          price_change = position[:entry_price] * price_change_percent
          new_price = position[:entry_price] + price_change
          new_price = [new_price, 0.01].max # Ensure price doesn't go below 0.01

          old_pnl = position[:pnl]
          position[:current_price] = new_price
          position[:pnl] = (new_price - position[:entry_price]) * position[:quantity]
          position[:last_update] = Time.now

          updated_count += 1
          @logger.info "[PositionTracker] Manually updated #{key}: #{position[:entry_price].round(2)} -> #{new_price.round(2)} (#{price_change_percent.round(3) * 100}%), PnL: #{old_pnl.round(2)} -> #{position[:pnl].round(2)}"
        end

        if updated_count.positive?
          @logger.info "[PositionTracker] Updated #{updated_count} positions with simulated price movements"
          # Save updated positions
          save_positions unless @memory_only
        else
          @logger.debug "[PositionTracker] No positions needed updating (all already have current_price != entry_price)"
        end
      end

      def get_positions_summary
        total_pnl = get_total_pnl
        open_positions = @positions.values.count { |pos| pos[:quantity].positive? }
        closed_positions = @positions.size - open_positions

        # Calculate max profit and drawdown
        max_profit = @positions.values.map { |pos| pos[:pnl] }.max || 0.0
        max_drawdown = @positions.values.map { |pos| pos[:pnl].negative? ? pos[:pnl].abs : 0.0 }.max || 0.0

        # Count winning and losing trades
        winning_trades = @positions.values.count { |pos| pos[:pnl].positive? }
        losing_trades = @positions.values.count { |pos| pos[:pnl].negative? }

        summary = {
          total_positions: @positions.size,
          open_positions: open_positions,
          closed_positions: closed_positions,
          total_pnl: total_pnl,
          max_profit: max_profit,
          max_drawdown: max_drawdown,
          winning_trades: winning_trades,
          losing_trades: losing_trades,
          positions: {},
        }

        @positions.each do |key, position|
          summary[:positions][key] = {
            symbol: position[:symbol],
            option_type: position[:option_type],
            strike: position[:strike],
            quantity: position[:quantity],
            entry_price: position[:entry_price],
            current_price: position[:current_price],
            pnl: position[:pnl],
            created_at: position[:created_at],
          }
        end

        summary
      end

      def get_underlying_summary
        summary = {}
        @underlying_prices.each do |symbol, data|
          summary[symbol] = {
            instrument_id: data[:instrument_id],
            last_price: data[:last_price],
            last_update: data[:last_update],
            subscribed: data[:subscribed],
          }
        end
        summary
      end

      # Save all data at end of session (even in memory-only mode)
      def save_session_data
        save_positions
        save_underlying_prices
        @logger.info "[PositionTracker] Session data saved"
      end

      def setup_websocket_handlers
        return unless @websocket_manager

        @websocket_manager.on_price_update do |price_data|
          handle_price_update(price_data)
        end
      end

      private

      def handle_price_update(price_data)
        instrument_id = price_data[:instrument_id]
        last_price = price_data[:last_price]
        timestamp = price_data[:timestamp]

        @logger.info "[PositionTracker] Received price update: #{instrument_id} = #{last_price}"

        # Update underlying prices
        @underlying_prices.each_value do |data|
          next unless data[:instrument_id] == instrument_id

          data[:last_price] = last_price
          data[:last_update] = timestamp
          @logger.info "[PositionTracker] Updated underlying #{instrument_id} price: #{last_price}"
          break
        end

        # Update position prices
        updated_positions = 0
        @positions.each_value do |position|
          next unless position[:instrument_id] == instrument_id

          old_price = position[:current_price]
          position[:current_price] = last_price
          position[:last_update] = timestamp
          position[:pnl] = (last_price - position[:entry_price]) * position[:quantity]
          updated_positions += 1
          @logger.info "[PositionTracker] Updated position #{position[:symbol]} #{position[:option_type]}: #{old_price} -> #{last_price}, PnL: #{position[:pnl]}"
        end

        @logger.info "[PositionTracker] Updated #{updated_positions} positions for instrument #{instrument_id}"

        # Save updated data only if not memory-only
        save_underlying_prices unless @memory_only
        save_positions unless @memory_only
      end

      def load_positions
        return unless File.exist?(@position_file)

        begin
          data = JSON.parse(File.read(@position_file))
          @positions = data.transform_keys(&:to_s).transform_values do |pos|
            pos.transform_keys(&:to_sym).tap do |p|
              p[:created_at] = Time.parse(p[:created_at]) if p[:created_at]
              p[:last_update] = Time.parse(p[:last_update]) if p[:last_update]
            end
          end
          @logger.info "[PositionTracker] Loaded #{@positions.size} existing positions"
        rescue StandardError => e
          @logger.error "[PositionTracker] Failed to load positions: #{e.message}"
          @positions = {}
        end
      end

      def save_positions
        FileUtils.mkdir_p(File.dirname(@position_file))

        begin
          File.write(@position_file, JSON.pretty_generate(@positions))
        rescue StandardError => e
          @logger.error "[PositionTracker] Failed to save positions: #{e.message}"
        end
      end

      def load_underlying_prices
        return unless File.exist?(@price_file)

        begin
          data = JSON.parse(File.read(@price_file))
          @underlying_prices = data.transform_keys(&:to_s).transform_values do |price|
            price.transform_keys(&:to_sym).tap do |p|
              p[:last_update] = Time.parse(p[:last_update]) if p[:last_update]
            end
          end
          @logger.info "[PositionTracker] Loaded #{@underlying_prices.size} underlying prices"
        rescue StandardError => e
          @logger.error "[PositionTracker] Failed to load underlying prices: #{e.message}"
          @underlying_prices = {}
        end
      end

      def save_underlying_prices
        FileUtils.mkdir_p(File.dirname(@price_file))

        begin
          File.write(@price_file, JSON.pretty_generate(@underlying_prices))
        rescue StandardError => e
          @logger.error "[PositionTracker] Failed to save underlying prices: #{e.message}"
        end
      end
    end
  end
end
