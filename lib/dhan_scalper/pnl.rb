module DhanScalper::PnL
  module_function
  def round_trip_orders(charge_per_order) = 2 * charge_per_order
  def net(entry:, ltp:, lot_size:, qty_lots:, charge_per_order:)
    ((ltp - entry) * (lot_size * qty_lots)) - round_trip_orders(charge_per_order)
  end
end