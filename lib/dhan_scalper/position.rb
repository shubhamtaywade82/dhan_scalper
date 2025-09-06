# frozen_string_literal: true

module DhanScalper
  class Position
    attr_accessor :symbol, :security_id, :side, :entry_price, :quantity, :current_price, :pnl
    attr_accessor :option_type, :strike, :expiry, :timestamp, :exit_price, :exit_reason, :exit_timestamp

    def initialize(security_id:, side:, entry_price:, quantity:, symbol: nil, current_price: nil, pnl: 0.0,
                   option_type: nil, strike: nil, expiry: nil, timestamp: nil)
      @symbol = symbol
      @security_id = security_id
      @side = side
      @entry_price = entry_price
      @quantity = quantity
      @current_price = current_price || entry_price
      @pnl = pnl
      @option_type = option_type
      @strike = strike
      @expiry = expiry
      @timestamp = timestamp || Time.now
      @exit_price = nil
      @exit_reason = nil
      @exit_timestamp = nil
    end

    def update_price(new_price)
      @current_price = new_price
      calculate_pnl
    end

    def calculate_pnl
      @pnl = case @side.upcase
             when "BUY"
               (@current_price - @entry_price) * @quantity
             when "SELL"
               (@entry_price - @current_price) * @quantity
             else
               0.0
             end
      @pnl
    end

    def pnl_percentage
      return 0.0 if @entry_price.zero?
      ((@current_price - @entry_price) / @entry_price) * 100
    end

    def closed?
      !@exit_price.nil?
    end

    def open?
      @exit_price.nil?
    end

    def close!(exit_price, reason)
      @exit_price = exit_price
      @exit_reason = reason
      @exit_timestamp = Time.now
      update_price(exit_price)
    end

    def to_h
      {
        symbol: @symbol,
        security_id: @security_id,
        side: @side,
        entry_price: @entry_price,
        quantity: @quantity,
        current_price: @current_price,
        pnl: @pnl,
        pnl_percentage: pnl_percentage,
        option_type: @option_type,
        strike: @strike,
        expiry: @expiry,
        timestamp: @timestamp,
        exit_price: @exit_price,
        exit_reason: @exit_reason,
        exit_timestamp: @exit_timestamp,
        closed: closed?
      }
    end

    def to_s
      option_info = @option_type ? " #{@option_type} #{@strike}" : ""
      status = closed? ? "CLOSED" : "OPEN"
      exit_info = closed? ? " (Exit: #{@exit_price}, Reason: #{@exit_reason})" : ""

      "#{status}#{option_info}: #{@side} #{@quantity} #{@symbol || @security_id} @ #{@entry_price} " \
      "(Current: #{@current_price}, P&L: #{@pnl.round(2)}, #{pnl_percentage.round(1)}%)#{exit_info}"
    end
  end
end
