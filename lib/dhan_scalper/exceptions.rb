# frozen_string_literal: true

module DhanScalper
  # Base exception class for all DhanScalper errors
  class Error < StandardError; end

  # Trading-related exceptions
  class TradingError < Error; end
  class InsufficientFunds < TradingError; end
  class OversellError < TradingError; end
  class InvalidQuantity < TradingError; end
  class InvalidOrder < TradingError; end

  # Balance-related exceptions
  class BalanceError < Error; end
  class InvalidBalanceOperation < BalanceError; end

  # Configuration exceptions
  class ConfigurationError < Error; end
  class InvalidConfiguration < ConfigurationError; end

  # Market data exceptions
  class MarketDataError < Error; end
  class PriceNotFound < MarketDataError; end
  class InvalidInstrument < MarketDataError; end

  # WebSocket exceptions
  class WebSocketError < Error; end
  class ConnectionError < WebSocketError; end
  class SubscriptionError < WebSocketError; end

  # Position tracking exceptions
  class PositionError < Error; end
  class PositionNotFound < PositionError; end
  class InvalidPositionOperation < PositionError; end
end
