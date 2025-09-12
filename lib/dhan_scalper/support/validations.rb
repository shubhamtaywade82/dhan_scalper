# frozen_string_literal: true

require_relative "money"

module DhanScalper
  module Support
    module Validations
      def self.validate_quantity(quantity, lot_size)
        raise DhanScalper::InvalidQuantity, "Quantity must be positive" if quantity <= 0
        raise DhanScalper::InvalidQuantity, "Quantity must be a multiple of lot size #{lot_size}" unless (quantity % lot_size).zero?
      end

      def self.validate_balance_sufficient(available_balance, required_amount)
        available_bd = DhanScalper::Support::Money.bd(available_balance)
        required_bd = DhanScalper::Support::Money.bd(required_amount)

        if DhanScalper::Support::Money.less_than?(available_bd, required_bd)
          raise DhanScalper::InsufficientFunds,
                "Insufficient funds: required #{DhanScalper::Support::Money.dec(required_bd)}, " \
                "available #{DhanScalper::Support::Money.dec(available_bd)}"
        end
      end

      def self.validate_position_sufficient(position_qty, sell_qty)
        if sell_qty > position_qty
          raise DhanScalper::OversellError,
                "Cannot sell #{sell_qty} units, only #{position_qty} units available"
        end
      end

      def self.validate_price_positive(price)
        raise DhanScalper::InvalidOrder, "Price must be positive" if price <= 0
      end

      def self.validate_instrument_id(instrument_id)
        raise DhanScalper::InvalidInstrument, "Instrument ID cannot be nil or empty" if instrument_id.nil? || instrument_id.to_s.empty?
      end

      def self.validate_segment(segment)
        valid_segments = %w[IDX_I NSE_EQ NSE_FNO BSE_FNO]
        unless valid_segments.include?(segment)
          raise DhanScalper::InvalidInstrument, "Invalid segment: #{segment}. Must be one of: #{valid_segments.join(', ')}"
        end
      end
    end
  end
end
