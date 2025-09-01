module DhanScalper
  module Brokers
    Order = Struct.new(:id, :security_id, :side, :qty, :avg_price)
    class Base
      def buy_market(segment:, security_id:, quantity:)  = raise NotImplementedError
      def sell_market(segment:, security_id:, quantity:) = raise NotImplementedError
      def name = self.class.name.split("::").last
    end
  end
end