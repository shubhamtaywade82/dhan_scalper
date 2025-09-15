# frozen_string_literal: true

require_relative '../support/money'
require_relative '../stores/redis_store'

module DhanScalper
  module Services
    # Enhanced position tracker that supports weighted averages and partial exits
    class EnhancedPositionTracker
      def initialize(balance_provider: nil, session_id: nil, redis_store: nil)
        @positions = {} # Key: "#{exchange_segment}_#{security_id}_#{side}"
        @realized_pnl = DhanScalper::Support::Money.bd(0)
        @balance_provider = balance_provider
        @session_id = session_id || generate_session_id
        @redis_store = redis_store || DhanScalper::Stores::RedisStore.new

        # Connect to Redis if not already connected
        @redis_store.connect unless @redis_store.redis

        # Load existing positions from Redis
        load_positions_from_redis
      end

      # Add or update a position with weighted averaging
      def add_position(exchange_segment:, security_id:, side:, quantity:, price:, fee: nil, option_type: nil,
                       strike_price: nil, expiry_date: nil, underlying_symbol: nil, symbol: nil)
        key = position_key(exchange_segment, security_id, side)
        price_bd = DhanScalper::Support::Money.bd(price)
        quantity_bd = DhanScalper::Support::Money.bd(quantity)
        fee_bd = DhanScalper::Support::Money.bd(fee || DhanScalper::Config.fee)

        if @positions[key]
          # Update existing position with weighted average
          update_existing_position(key, quantity_bd, price_bd, fee_bd)
        else
          # Create new position
          create_new_position(key, exchange_segment, security_id, side, quantity_bd, price_bd, fee_bd, option_type,
                              strike_price, expiry_date, underlying_symbol, symbol)
        end

        # Save to Redis
        save_position_to_redis(key)

        @positions[key]
      end

      # Partial exit from a position
      def partial_exit(exchange_segment:, security_id:, side:, quantity:, price:, fee: nil)
        key = position_key(exchange_segment, security_id, side)
        position = @positions[key]
        return nil unless position

        price_bd = DhanScalper::Support::Money.bd(price)
        quantity_bd = DhanScalper::Support::Money.bd(quantity)
        fee_bd = DhanScalper::Support::Money.bd(fee || DhanScalper::Config.fee)

        # Calculate how much we can actually sell
        sellable_quantity = DhanScalper::Support::Money.min(quantity_bd, position[:net_qty])

        if DhanScalper::Support::Money.zero?(sellable_quantity)
          return nil # Nothing to sell
        end

        # Calculate realized PnL for this partial exit
        realized_pnl = DhanScalper::Support::Money.multiply(
          DhanScalper::Support::Money.subtract(price_bd, position[:buy_avg]),
          sellable_quantity
        )

        # Update realized PnL
        @realized_pnl = DhanScalper::Support::Money.add(@realized_pnl, realized_pnl)
        position[:realized_pnl] = DhanScalper::Support::Money.add(position[:realized_pnl], realized_pnl)

        # Update position quantities
        position[:net_qty] = DhanScalper::Support::Money.subtract(position[:net_qty], sellable_quantity)
        position[:sell_qty] = DhanScalper::Support::Money.add(position[:sell_qty], sellable_quantity)

        # Update sell average (weighted)
        if DhanScalper::Support::Money.zero?(position[:sell_qty])
          position[:sell_avg] = price_bd
        else
          # Calculate weighted average: (old_avg * old_qty + new_price * new_qty) / (old_qty + new_qty)
          old_sell_qty = DhanScalper::Support::Money.subtract(position[:sell_qty], sellable_quantity)
          total_sell_value = DhanScalper::Support::Money.add(
            DhanScalper::Support::Money.multiply(position[:sell_avg], old_sell_qty),
            DhanScalper::Support::Money.multiply(price_bd, sellable_quantity)
          )
          position[:sell_avg] = DhanScalper::Support::Money.divide(
            total_sell_value,
            position[:sell_qty]
          )
        end

        # Update day quantities
        position[:day_sell_qty] = DhanScalper::Support::Money.add(position[:day_sell_qty], sellable_quantity)

        # Calculate net proceeds (gross proceeds - fee)
        gross_proceeds = DhanScalper::Support::Money.multiply(price_bd, sellable_quantity)
        net_proceeds = DhanScalper::Support::Money.subtract(gross_proceeds, fee_bd)

        # Update timestamps
        position[:last_updated] = Time.now

        # Save to Redis
        save_position_to_redis(key)

        # Keep closed positions (net_qty can be zero) for reporting consistency

        {
          position: position,
          realized_pnl: realized_pnl,
          net_proceeds: net_proceeds,
          sold_quantity: sellable_quantity
        }
      end

      # Get position by key
      def get_position(exchange_segment:, security_id:, side:)
        key = position_key(exchange_segment, security_id, side)
        @positions[key]
      end

      # Get all positions
      def get_positions
        @positions.values
      end

      # Clear all positions (for testing)
      def clear_positions
        @positions.clear
        @realized_pnl = DhanScalper::Support::Money.bd(0)
      end

      # Get realized PnL
      attr_reader :realized_pnl

      # Update unrealized PnL for all positions
      def update_unrealized_pnl(ltp_provider)
        total_unrealized = DhanScalper::Support::Money.bd(0)

        @positions.each_value do |position|
          current_price = ltp_provider.call(position[:exchange_segment], position[:security_id])
          next unless current_price&.positive?

          price_bd = DhanScalper::Support::Money.bd(current_price)
          position[:current_price] = price_bd

          # Calculate unrealized PnL on remaining net quantity
          if DhanScalper::Support::Money.positive?(position[:net_qty])
            unrealized = DhanScalper::Support::Money.multiply(
              DhanScalper::Support::Money.subtract(price_bd, position[:buy_avg]),
              position[:net_qty]
            )
            position[:unrealized_pnl] = unrealized
            total_unrealized = DhanScalper::Support::Money.add(total_unrealized, unrealized)
          else
            position[:unrealized_pnl] = DhanScalper::Support::Money.bd(0)
          end
        end

        total_unrealized
      end

      # Reset day quantities (call at start of new trading day)
      def reset_day_quantities
        @positions.each_value do |position|
          position[:day_buy_qty] = DhanScalper::Support::Money.bd(0)
          position[:day_sell_qty] = DhanScalper::Support::Money.bd(0)
        end
      end

      # Remove position completely
      def remove_position(exchange_segment:, security_id:, side:)
        key = position_key(exchange_segment, security_id, side)
        @positions.delete(key)
      end

      # Update unrealized PnL for a specific position
      def update_position_unrealized_pnl(exchange_segment:, security_id:, side:, unrealized_pnl:)
        key = position_key(exchange_segment, security_id, side)
        position = @positions[key]
        return false unless position

        position[:unrealized_pnl] = DhanScalper::Support::Money.bd(unrealized_pnl)
        position[:last_updated] = Time.now

        # Save updated position to Redis
        save_position_to_redis(key)

        true
      end

      # Update current price for a position
      def update_current_price(exchange_segment:, security_id:, side:, current_price:)
        key = position_key(exchange_segment, security_id, side)
        position = @positions[key]
        return false unless position

        position[:current_price] = DhanScalper::Support::Money.bd(current_price)
        true
      end

      private

      def position_key(exchange_segment, security_id, side)
        # For options, we want to aggregate by underlying symbol, not individual security_id
        # This allows multiple strikes of the same underlying to be treated as one position
        if security_id.to_s.match?(/^\d+$/) # If it's a numeric security_id (likely an option)
          # Extract underlying symbol from security_id if possible
          # For now, we'll use a simplified approach - group by first few digits
          base_id = security_id.to_s[0..2] # Use first 3 digits as base
          "#{exchange_segment}_#{base_id}_#{side.upcase}"
        else
          "#{exchange_segment}_#{security_id}_#{side.upcase}"
        end
      end

      def create_new_position(key, exchange_segment, security_id, side, quantity_bd, price_bd, fee_bd,
                              option_type = nil, strike_price = nil, expiry_date = nil, underlying_symbol = nil, symbol = nil)
        @positions[key] = {
          exchange_segment: exchange_segment,
          security_id: security_id,
          side: side.upcase,
          buy_qty: quantity_bd,
          buy_avg: price_bd,
          net_qty: quantity_bd,
          sell_qty: DhanScalper::Support::Money.bd(0),
          sell_avg: DhanScalper::Support::Money.bd(0),
          day_buy_qty: quantity_bd,
          day_sell_qty: DhanScalper::Support::Money.bd(0),
          current_price: price_bd,
          unrealized_pnl: DhanScalper::Support::Money.bd(0),
          realized_pnl: DhanScalper::Support::Money.bd(0),
          entry_fee: fee_bd, # Store the entry fee
          multiplier: 1,
          lot_size: 75,
          option_type: option_type,
          strike_price: strike_price,
          expiry_date: expiry_date,
          underlying_symbol: underlying_symbol,
          symbol: symbol,
          created_at: Time.now,
          last_updated: Time.now
        }
      end

      def update_existing_position(key, quantity_bd, price_bd, fee_bd)
        position = @positions[key]

        # Calculate new weighted average
        total_buy_qty = DhanScalper::Support::Money.add(position[:buy_qty], quantity_bd)
        total_buy_value = DhanScalper::Support::Money.add(
          DhanScalper::Support::Money.multiply(position[:buy_avg], position[:buy_qty]),
          DhanScalper::Support::Money.multiply(price_bd, quantity_bd)
        )

        # Update quantities
        position[:buy_qty] = total_buy_qty
        position[:buy_avg] = DhanScalper::Support::Money.divide(total_buy_value, total_buy_qty)
        position[:net_qty] = DhanScalper::Support::Money.add(position[:net_qty], quantity_bd)
        position[:day_buy_qty] = DhanScalper::Support::Money.add(position[:day_buy_qty], quantity_bd)

        # Update entry fee (add new fee to existing)
        position[:entry_fee] =
          DhanScalper::Support::Money.add(position[:entry_fee] || DhanScalper::Support::Money.bd(0), fee_bd)
        position[:last_updated] = Time.now
      end

      # Get comprehensive positions summary
      def get_positions_summary
        total_positions = @positions.size
        open_positions = @positions.values.count { |pos| DhanScalper::Support::Money.positive?(pos[:net_qty]) }
        closed_positions = total_positions - open_positions

        # Calculate total P&L
        total_unrealized_pnl = @positions.values.sum do |pos|
          DhanScalper::Support::Money.dec(pos[:unrealized_pnl] || DhanScalper::Support::Money.bd(0))
        end

        total_realized_pnl = @positions.values.sum do |pos|
          DhanScalper::Support::Money.dec(pos[:realized_pnl] || DhanScalper::Support::Money.bd(0))
        end

        total_pnl = total_unrealized_pnl + total_realized_pnl

        # Calculate max profit and drawdown
        pnl_values = @positions.values.map do |pos|
          DhanScalper::Support::Money.dec(pos[:unrealized_pnl] || DhanScalper::Support::Money.bd(0))
        end

        max_profit = pnl_values.empty? ? 0.0 : pnl_values.max

        drawdown_values = @positions.values.map do |pos|
          pnl = DhanScalper::Support::Money.dec(pos[:unrealized_pnl] || DhanScalper::Support::Money.bd(0))
          pnl.negative? ? pnl.abs : 0.0
        end

        max_drawdown = drawdown_values.empty? ? 0.0 : drawdown_values.max

        # Count winning and losing trades
        winning_trades = @positions.values.count do |pos|
          pnl = DhanScalper::Support::Money.dec(pos[:unrealized_pnl] || DhanScalper::Support::Money.bd(0))
          pnl.positive?
        end

        losing_trades = @positions.values.count do |pos|
          pnl = DhanScalper::Support::Money.dec(pos[:unrealized_pnl] || DhanScalper::Support::Money.bd(0))
          pnl.negative?
        end

        # Format positions for reporting
        @positions.values.map do |pos|
          {
            symbol: pos[:symbol] || pos[:underlying_symbol] || 'UNKNOWN',
            option_type: pos[:option_type] || 'UNKNOWN',
            strike: pos[:strike_price] || 0,
            quantity: DhanScalper::Support::Money.dec(pos[:net_qty] || DhanScalper::Support::Money.bd(0)),
            entry_price: DhanScalper::Support::Money.dec(pos[:buy_avg] || DhanScalper::Support::Money.bd(0)),
            current_price: DhanScalper::Support::Money.dec(pos[:current_price] || pos[:buy_avg] || DhanScalper::Support::Money.bd(0)),
            pnl: DhanScalper::Support::Money.dec(pos[:unrealized_pnl] || DhanScalper::Support::Money.bd(0)),
            created_at: pos[:created_at]&.strftime('%Y-%m-%d %H:%M:%S %z') || Time.now.strftime('%Y-%m-%d %H:%M:%S %z')
          }
        end

        {
          total_positions: total_positions,
          open_positions: open_positions,
          closed_positions: closed_positions,
          total_pnl: total_pnl,
          max_profit: max_profit,
          max_drawdown: max_drawdown,
          winning_trades: winning_trades,
          losing_trades: losing_trades,
          positions: @positions.transform_values do |pos|
            {
              symbol: pos[:symbol] || pos[:underlying_symbol] || 'UNKNOWN',
              option_type: pos[:option_type] || 'UNKNOWN',
              strike: pos[:strike_price] || 0,
              quantity: DhanScalper::Support::Money.dec(pos[:net_qty] || DhanScalper::Support::Money.bd(0)),
              entry_price: DhanScalper::Support::Money.dec(pos[:buy_avg] || DhanScalper::Support::Money.bd(0)),
              current_price: DhanScalper::Support::Money.dec(pos[:current_price] || pos[:buy_avg] || DhanScalper::Support::Money.bd(0)),
              pnl: DhanScalper::Support::Money.dec(pos[:unrealized_pnl] || DhanScalper::Support::Money.bd(0)),
              created_at: pos[:created_at]&.strftime('%Y-%m-%d %H:%M:%S %z') || Time.now.strftime('%Y-%m-%d %H:%M:%S %z')
            }
          end
        }
      end

      # Save session data to file
      def save_session_data
        # This method can be implemented to save position data to a file
        # For now, it's a no-op
      end

      def generate_session_id
        "PAPER_#{Time.now.strftime('%Y%m%d')}"
      end

      def load_positions_from_redis
        positions_key = "dhan_scalper:v1:positions:#{@session_id}"
        position_ids = @redis_store.redis.smembers(positions_key)

        position_ids.each do |position_id|
          position_key = "dhan_scalper:v1:position:#{position_id}"
          position_data = @redis_store.redis.hgetall(position_key)

          next if position_data.empty?

          # Convert string values back to appropriate types
          position = {
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
            option_type: position_data['option_type'],
            strike_price: position_data['strike_price']&.to_i,
            expiry_date: position_data['expiry_date'],
            underlying_symbol: position_data['underlying_symbol'],
            symbol: position_data['symbol'],
            created_at: position_data['created_at'] ? Time.parse(position_data['created_at']) : Time.now,
            last_updated: position_data['last_updated'] ? Time.parse(position_data['last_updated']) : Time.now
          }

          @positions[position_id] = position
        end

        DhanScalper::Support::Logger.debug(
          "Loaded #{@positions.size} positions from Redis",
          component: 'EnhancedPositionTracker'
        )
      end

      def save_position_to_redis(key)
        position = @positions[key]
        return unless position

        position_id = key
        position_key = "dhan_scalper:v1:position:#{position_id}"

        # Convert position to Redis-compatible format
        position_data = {
          exchange_segment: position[:exchange_segment],
          security_id: position[:security_id],
          side: position[:side],
          net_qty: DhanScalper::Support::Money.dec(position[:net_qty]).to_s,
          buy_qty: DhanScalper::Support::Money.dec(position[:buy_qty]).to_s,
          buy_avg: DhanScalper::Support::Money.dec(position[:buy_avg]).to_s,
          sell_qty: DhanScalper::Support::Money.dec(position[:sell_qty]).to_s,
          sell_avg: DhanScalper::Support::Money.dec(position[:sell_avg]).to_s,
          day_buy_qty: DhanScalper::Support::Money.dec(position[:day_buy_qty]).to_s,
          day_sell_qty: DhanScalper::Support::Money.dec(position[:day_sell_qty]).to_s,
          realized_pnl: DhanScalper::Support::Money.dec(position[:realized_pnl]).to_s,
          unrealized_pnl: DhanScalper::Support::Money.dec(position[:unrealized_pnl]).to_s,
          current_price: DhanScalper::Support::Money.dec(position[:current_price]).to_s,
          option_type: position[:option_type] || '',
          strike_price: position[:strike_price].to_s,
          expiry_date: position[:expiry_date] || '',
          underlying_symbol: position[:underlying_symbol] || '',
          symbol: position[:symbol] || '',
          created_at: position[:created_at]&.iso8601 || Time.now.iso8601,
          last_updated: position[:last_updated]&.iso8601 || Time.now.iso8601
        }

        @redis_store.redis.hset(position_key, position_data)
        @redis_store.redis.expire(position_key, 86_400) # 24 hours TTL

        # Add to positions set
        positions_key = "dhan_scalper:v1:positions:#{@session_id}"
        @redis_store.redis.sadd(positions_key, position_id)
        @redis_store.redis.expire(positions_key, 86_400) # 24 hours TTL

        DhanScalper::Support::Logger.debug(
          "Saved position to Redis - key: #{position_key}",
          component: 'EnhancedPositionTracker'
        )
      end
    end
  end
end
