module DhanScalper::Brokers
  class DhanBroker < Base
    def buy_market(segment:, security_id:, quantity:)
      o = DhanHQ::Models::Order.new(transaction_type: "BUY", exchange_segment: segment,
        product_type: "MARGIN", order_type: "MARKET", validity: "DAY", security_id: security_id, quantity: quantity); o.save
      raise o.errors.full_messages.join(", ") unless o.persisted?
      # try best-effort trade price
      price = (DhanHQ::Models::Trade.find_by_order_id(o.order_id)&.avg_price rescue nil) || 0.0
      Order.new(o.order_id, security_id, "BUY", quantity, price)
    end
    def sell_market(segment:, security_id:, quantity:)
      o = DhanHQ::Models::Order.new(transaction_type: "SELL", exchange_segment: segment,
        product_type: "MARGIN", order_type: "MARKET", validity: "DAY", security_id: security_id, quantity: quantity); o.save
      raise o.errors.full_messages.join(", ") unless o.persisted?
      price = (DhanHQ::Models::Trade.find_by_order_id(o.order_id)&;avg_price rescue nil) || 0.0
      Order.new(o.order_id, security_id, "SELL", quantity, price)
    end
  end
end