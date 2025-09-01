module DhanScalper::Brokers
  class PaperBroker < Base
    def buy_market(segment:, security_id:, quantity:)
      price = DhanScalper::TickCache.ltp(segment, security_id)&.to_f || 0.0
      Order.new("P-#{Time.now.to_f}", security_id, "BUY", quantity, price)
    end
    def sell_market(segment:, security_id:, quantity:)
      price = DhanScalper::TickCache.ltp(segment, security_id)&.to_f || 0.0
      Order.new("P-#{Time.now.to_f}", security_id, "SELL", quantity, price)
    end
  end
end