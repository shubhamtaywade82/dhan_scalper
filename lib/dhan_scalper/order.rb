# frozen_string_literal: true

module DhanScalper
  class Order
    attr_reader :id, :security_id, :side, :quantity, :price, :timestamp

    def initialize(id, security_id, side, quantity, price)
      @id = id
      @security_id = security_id
      @side = side.upcase
      @quantity = quantity.to_i
      @price = price.to_f
      @timestamp = Time.now
    end

    def buy?
      @side == "BUY"
    end

    def sell?
      @side == "SELL"
    end

    def total_value
      @quantity * @price
    end

    def to_hash
      {
        id: @id,
        security_id: @security_id,
        side: @side,
        quantity: @quantity,
        price: @price,
        timestamp: @timestamp,
      }
    end

    def to_s
      "#{@side} #{@quantity} #{@security_id} @ ₹#{@price}"
    end
  end
end
