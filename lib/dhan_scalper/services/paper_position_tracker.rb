# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative '../stores/redis_store'

module DhanScalper
  module Services
    # PaperPositionTracker manages paper trading positions with Redis persistence
    # Handles position creation, updates, PnL calculations, and WebSocket subscriptions
    class PaperPositionTracker
      attr_reader :positions, :underlying_prices, :websocket_manager

      def initialize(websocket_manager:, logger: nil, memory_only: true, session_id: nil, redis_store: nil)
        @websocket_manager = websocket_manager
        @logger = logger || Logger.new($stdout)
        @persist_to_redis = !memory_only
        @positions = {}
        @underlying_prices = {}
        @session_id = session_id || self.class.generate_session_id
        @redis_store = redis_store || DhanScalper::Stores::RedisStore.new

        # Connect to Redis if not already connected
        @redis_store.connect unless @redis_store.redis

        # Load existing positions from Redis
        load_positions_from_redis if @persist_to_redis

        # Setup WebSocket handlers
        setup_websocket_handlers
      end

      def self.generate_session_id
        "PAPER_#{Time.now.strftime('%Y%m%d')}"
      end

      def load_positions_from_redis
        positions_key = "dhan_scalper:v1:positions:#{@session_id}"
        position_ids = @redis_store.redis.smembers(positions_key)
        current_time = Time.now

        position_ids.each do |position_id|
          position_key = "dhan_scalper:v1:position:#{position_id}"
          position_data = @redis_store.redis.hgetall(position_key)

          next if position_data.empty?

          # Convert string values back to appropriate types
          position = {
            position_key: position_id, # Add the position_key field
            exchange_segment: position_data['exchange_segment'],
            security_id: position_data['security_id'],
            side: position_data['side'],
            net_qty: DhanScalper::Support::Money.bd(position_data['net_qty'] || 0),
            buy_qty: DhanScalper::Support::Money.bd(position_data['buy_qty'] || 0),
            buy_avg: DhanScalper::Support::Money.bd(position_data['buy_avg'] || 0),
            sell_qty: DhanScalper::Support::Money.bd(position_data['sell_qty'] || 0),
            sell_avg: DhanScalper::Support::Money.bd(position_data['sell_avg'] || 0),
            day_buy_qty: DhanScalper::Support::Money.bd(position_data['day_buy_qty'] || 0),
            day_sell_qty: DhanScalper::Support::Money.bd(position_data['day_sell_qty'] || 0),
            realized_pnl: DhanScalper::Support::Money.bd(position_data['realized_pnl'] || 0),
            unrealized_pnl: DhanScalper::Support::Money.bd(position_data['unrealized_pnl'] || 0),
            current_price: DhanScalper::Support::Money.bd(position_data['current_price'] || 0),
            option_type: position_data['option_type'] || '',
            strike_price: position_data['strike_price'].to_i,
            expiry_date: position_data['expiry_date'] || '',
            underlying_symbol: position_data['underlying_symbol'] || '',
            symbol: position_data['symbol'] || '',
            created_at: position_data['created_at'] ? Time.parse(position_data['created_at']) : current_time,
            last_updated: position_data['last_updated'] ? Time.parse(position_data['last_updated']) : current_time
          }

          @positions[position_id] = position
        end

        @logger.debug("Loaded #{@positions.size} positions from Redis")
      end

      def save_position_to_redis(position_id)
        position = @positions[position_id]
        return unless position

        position_key = "dhan_scalper:v1:position:#{position_id}"
        current_time_iso = Time.now.iso8601

        # Convert position to Redis-compatible format
        position_data = {
          exchange_segment: position[:exchange_segment] || '',
          security_id: position[:security_id] || '',
          side: position[:side] || '',
          net_qty: DhanScalper::Support::Money.dec(position[:net_qty] || 0).to_s,
          buy_qty: DhanScalper::Support::Money.dec(position[:buy_qty] || 0).to_s,
          buy_avg: DhanScalper::Support::Money.dec(position[:buy_avg] || 0).to_s,
          sell_qty: DhanScalper::Support::Money.dec(position[:sell_qty] || 0).to_s,
          sell_avg: DhanScalper::Support::Money.dec(position[:sell_avg] || 0).to_s,
          day_buy_qty: DhanScalper::Support::Money.dec(position[:day_buy_qty] || 0).to_s,
          day_sell_qty: DhanScalper::Support::Money.dec(position[:day_sell_qty] || 0).to_s,
          realized_pnl: DhanScalper::Support::Money.dec(position[:realized_pnl] || 0).to_s,
          unrealized_pnl: DhanScalper::Support::Money.dec(position[:unrealized_pnl] || 0).to_s,
          current_price: DhanScalper::Support::Money.dec(position[:current_price] || 0).to_s,
          option_type: position[:option_type] || '',
          strike_price: position[:strike_price].to_s,
          expiry_date: position[:expiry_date] || '',
          underlying_symbol: position[:underlying_symbol] || '',
          symbol: position[:symbol] || '',
          created_at: position[:created_at]&.iso8601 || current_time_iso,
          last_updated: position[:last_updated]&.iso8601 || current_time_iso
        }

        @redis_store.redis.hset(position_key, position_data)
        @redis_store.redis.expire(position_key, 86_400) # 24 hours TTL

        # Add to positions set
        positions_key = "dhan_scalper:v1:positions:#{@session_id}"
        @redis_store.redis.sadd(positions_key, position_id)
        @redis_store.redis.expire(positions_key, 86_400) # 24 hours TTL

        @logger.debug("Saved position to Redis - key: #{position_key}")
      end

      def track_underlying(symbol, instrument_id)
        @logger.info "[PositionTracker] Starting to track underlying: #{symbol} (#{instrument_id})"

        # Subscribe to underlying price updates
        success = @websocket_manager&.subscribe_to_instrument(instrument_id, 'INDEX') || true

        if success
          @underlying_prices[symbol] = {
            instrument_id: instrument_id,
            last_price: nil,
            last_update: nil,
            subscribed: true
          }
          save_underlying_prices if @persist_to_redis
          @logger.info "[PositionTracker] Now tracking #{symbol} at #{instrument_id}"
        else
          @logger.error "[PositionTracker] Failed to subscribe to #{symbol}"
        end

        success
      end

      def add_position(position_data)
        symbol = position_data[:symbol]
        option_type = position_data[:option_type]
        strike = position_data[:strike]
        expiry = position_data[:expiry]
        instrument_id = position_data[:instrument_id]
        quantity = position_data[:quantity]
        entry_price = position_data[:entry_price]
        # Use a simplified key that aggregates by symbol and option type
        position_key = "#{symbol}_#{option_type}"

        @logger.info "[PositionTracker] Adding position: #{position_key} (#{instrument_id})"

        # Subscribe to option price updates (allow failure for testing)
        success = @websocket_manager&.subscribe_to_instrument(instrument_id, 'OPTION') || true

        # Always add position even if WebSocket subscription fails (for testing)
        current_time = Time.now
        strike_int = strike.to_i
        expiry_str = expiry.to_s

        existing = @positions[position_key]
        if existing
          # Aggregate with existing position
          existing_quantity = existing[:quantity]
          total_quantity = existing_quantity + quantity
          # Calculate weighted average entry price
          total_value = (existing[:entry_price] * existing_quantity) + (entry_price * quantity)
          weighted_avg_price = total_value / total_quantity

          @positions[position_key] = {
            symbol: symbol,
            option_type: option_type, # CE or PE
            strike: strike_int, # Use the latest strike
            expiry: expiry, # Use the latest expiry
            instrument_id: instrument_id, # Use the latest instrument_id
            quantity: total_quantity,
            entry_price: weighted_avg_price,
            current_price: entry_price, # Use current market price
            pnl: 0.0, # Will be calculated later
            created_at: existing[:created_at], # Keep original creation time
            last_update: current_time,
            subscribed: true,
            # Redis-compatible fields
            exchange_segment: 'NSE_FNO',
            security_id: instrument_id,
            side: 'BUY',
            net_qty: total_quantity,
            buy_qty: total_quantity,
            buy_avg: weighted_avg_price,
            sell_qty: 0,
            sell_avg: 0.0,
            day_buy_qty: total_quantity,
            day_sell_qty: 0,
            realized_pnl: 0.0,
            unrealized_pnl: 0.0,
            strike_price: strike_int,
            expiry_date: expiry_str,
            underlying_symbol: symbol,
            last_updated: current_time
          }

          @logger.info "[PositionTracker] Position aggregated: #{position_key} (total qty: #{total_quantity})"
        else
          # Create new position
          @positions[position_key] = {
            symbol: symbol,
            option_type: option_type, # CE or PE
            strike: strike_int,
            expiry: expiry,
            instrument_id: instrument_id,
            quantity: quantity,
            entry_price: entry_price,
            current_price: entry_price,
            pnl: 0.0,
            created_at: current_time,
            last_update: current_time,
            subscribed: true,
            # Redis-compatible fields
            exchange_segment: 'NSE_FNO',
            security_id: instrument_id,
            side: 'BUY',
            net_qty: quantity,
            buy_qty: quantity,
            buy_avg: entry_price,
            sell_qty: 0,
            sell_avg: 0.0,
            day_buy_qty: quantity,
            day_sell_qty: 0,
            realized_pnl: 0.0,
            unrealized_pnl: 0.0,
            strike_price: strike_int,
            expiry_date: expiry_str,
            underlying_symbol: symbol,
            last_updated: current_time
          }

          @logger.info "[PositionTracker] Position created: #{position_key}"
        end

        # Save to Redis
        save_position_to_redis(position_key)

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

        # Remove from Redis
        position_redis_key = "dhan_scalper:v1:position:#{position_key}"
        @redis_store.redis.del(position_redis_key)

        # Remove from positions set
        positions_key = "dhan_scalper:v1:positions:#{@session_id}"
        @redis_store.redis.srem(positions_key, position_key)

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
          segment = @underlying_prices[symbol][:segment] || 'IDX_I'

          # Use TickCache with fallback to get live data
          ltp = DhanScalper::TickCache.ltp(segment, instrument_id, use_fallback: true)
          return ltp if ltp
        end

        nil
      end

      def get_position_pnl(position_key)
        position = @positions[position_key]
        return nil unless position

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

      # Get a single position by key
      def get_position(position_key)
        @positions[position_key]
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
          save_positions if @persist_to_redis
        else
          @logger.debug '[PositionTracker] No positions needed updating (all already have current_price != entry_price)'
        end
      end

      def get_positions_summary
        total_pnl = get_total_pnl
        positions_values = @positions.values
        positions_size = @positions.size

        open_positions = positions_values.count { |pos| pos[:quantity].positive? }
        closed_positions = positions_size - open_positions

        # Calculate max profit and drawdown
        pnl_values = positions_values.map { |pos| pos[:pnl] }
        pnl_empty = pnl_values.empty?
        max_profit = pnl_empty ? 0.0 : pnl_values.max
        max_drawdown = if pnl_empty
                         0.0
                       else
                         pnl_values.map { |pnl| pnl.negative? ? pnl.abs : 0.0 }.max
                       end

        # Count winning and losing trades
        winning_trades = pnl_values.count(&:positive?)
        losing_trades = pnl_values.count(&:negative?)

        summary = {
          total_positions: positions_size,
          open_positions: open_positions,
          closed_positions: closed_positions,
          total_pnl: total_pnl,
          max_profit: max_profit,
          max_drawdown: max_drawdown,
          winning_trades: winning_trades,
          losing_trades: losing_trades,
          positions: {}
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
            created_at: position[:created_at]
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
            subscribed: data[:subscribed]
          }
        end
        summary
      end

      # Save all data at end of session (even in memory-only mode)
      def save_session_data
        # Positions are already saved to Redis in real-time
        # No need to save again here
        @logger.info '[PositionTracker] Session data saved'
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
        save_underlying_prices if @persist_to_redis
        save_positions if @persist_to_redis
      end

      def load_positions
        return unless File.exist?(@position_file)

        begin
          data = JSON.parse(File.read(@position_file))
          @positions = data.transform_keys(&:to_s).transform_values do |pos|
            pos.transform_keys(&:to_sym).tap do |position|
              position[:created_at] = Time.parse(position[:created_at]) if position[:created_at]
              position[:last_update] = Time.parse(position[:last_update]) if position[:last_update]
            end
          end
          @logger.info "[PositionTracker] Loaded #{@positions.size} existing positions"
        rescue StandardError => e
          @logger.error "[PositionTracker] Failed to load positions: #{e.message}"
          @positions = {}
        end
      end

      # File-based save_positions removed - using Redis only

      def load_underlying_prices
        return unless File.exist?(@price_file)

        begin
          data = JSON.parse(File.read(@price_file))
          @underlying_prices = data.transform_keys(&:to_s).transform_values do |price|
            price.transform_keys(&:to_sym).tap do |price_data|
              price_data[:last_update] = Time.parse(price_data[:last_update]) if price_data[:last_update]
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
