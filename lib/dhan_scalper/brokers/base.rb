# frozen_string_literal: true

module DhanScalper
  module Brokers
    Order = Struct.new(:id, :security_id, :side, :qty, :avg_price)

    class Base
      def initialize(virtual_data_manager: nil)
        @virtual_data_manager = virtual_data_manager
      end

      def buy_market(segment:, security_id:, quantity:)  = raise NotImplementedError
      def sell_market(segment:, security_id:, quantity:) = raise NotImplementedError
      def name = self.class.name.split('::').last

      protected

      def log_order(order)
        @virtual_data_manager&.add_order(order)
      end

      def log_position(position)
        @virtual_data_manager&.add_position(position)
      end
    end
  end
end
