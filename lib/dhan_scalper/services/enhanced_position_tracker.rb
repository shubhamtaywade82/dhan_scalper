# frozen_string_literal: true

require_relative "../support/money"

module DhanScalper
  module Services
    # Enhanced position tracker that supports weighted averages and partial exits
    class EnhancedPositionTracker
      def initialize(balance_provider: nil)
        @positions = {} # Key: "#{exchange_segment}_#{security_id}_#{side}"
        @realized_pnl = DhanScalper::Support::Money.bd(0)
        @balance_provider = balance_provider
      end

      # Add or update a position with weighted averaging
      def add_position(exchange_segment:, security_id:, side:, quantity:, price:, fee: nil)
        key = position_key(exchange_segment, security_id, side)
        price_bd = DhanScalper::Support::Money.bd(price)
        quantity_bd = DhanScalper::Support::Money.bd(quantity)
        fee_bd = DhanScalper::Support::Money.bd(fee || DhanScalper::Config.fee)

        if @positions[key]
          # Update existing position with weighted average
          update_existing_position(key, quantity_bd, price_bd, fee_bd)
        else
          # Create new position
          create_new_position(key, exchange_segment, security_id, side, quantity_bd, price_bd, fee_bd)
        end

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
          sellable_quantity,
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
            DhanScalper::Support::Money.multiply(price_bd, sellable_quantity),
          )
          position[:sell_avg] = DhanScalper::Support::Money.divide(
            total_sell_value,
            position[:sell_qty],
          )
        end

        # Update day quantities
        position[:day_sell_qty] = DhanScalper::Support::Money.add(position[:day_sell_qty], sellable_quantity)

        # Calculate net proceeds (gross proceeds - fee)
        gross_proceeds = DhanScalper::Support::Money.multiply(price_bd, sellable_quantity)
        net_proceeds = DhanScalper::Support::Money.subtract(gross_proceeds, fee_bd)

        # Update timestamps
        position[:last_updated] = Time.now

        # Keep closed positions (net_qty can be zero) for reporting consistency

        {
          position: position,
          realized_pnl: realized_pnl,
          net_proceeds: net_proceeds,
          sold_quantity: sellable_quantity,
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
              position[:net_qty],
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

      # Update unrealized PnL for a position
      def update_unrealized_pnl(exchange_segment:, security_id:, side:, unrealized_pnl:)
        key = position_key(exchange_segment, security_id, side)
        position = @positions[key]
        return false unless position

        position[:unrealized_pnl] = DhanScalper::Support::Money.bd(unrealized_pnl)
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
        "#{exchange_segment}_#{security_id}_#{side.upcase}"
      end

      def create_new_position(key, exchange_segment, security_id, side, quantity_bd, price_bd, fee_bd)
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
          option_type: nil,
          strike_price: nil,
          expiry_date: nil,
          underlying_symbol: nil,
          symbol: nil,
          created_at: Time.now,
          last_updated: Time.now,
        }
      end

      def update_existing_position(key, quantity_bd, price_bd, fee_bd)
        position = @positions[key]

        # Calculate new weighted average
        total_buy_qty = DhanScalper::Support::Money.add(position[:buy_qty], quantity_bd)
        total_buy_value = DhanScalper::Support::Money.add(
          DhanScalper::Support::Money.multiply(position[:buy_avg], position[:buy_qty]),
          DhanScalper::Support::Money.multiply(price_bd, quantity_bd),
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
    end
  end
end
