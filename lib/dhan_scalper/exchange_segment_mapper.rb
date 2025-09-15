# frozen_string_literal: true

module DhanScalper
  class ExchangeSegmentMapper
    # Maps exchange and segment combinations to DhanHQ exchange segments
    # @param exchange [String, Symbol] Exchange name (e.g., "NSE", "BSE", "MCX")
    # @param segment [String, Symbol] Segment code (e.g., "E", "I", "D", "C", "M")
    # @return [String] DhanHQ exchange segment code
    # @raise [ArgumentError] If the exchange/segment combination is not supported
    def self.exchange_segment(exchange, segment)
      case [exchange.to_s.upcase.to_sym, segment.to_s.upcase.to_sym]
      when %i[NSE I], %i[BSE I] then 'IDX_I'
      when %i[NSE E] then 'NSE_EQ'
      when %i[BSE E] then 'BSE_EQ'
      when %i[NSE D] then 'NSE_FNO'
      when %i[BSE D] then 'BSE_FNO'
      when %i[NSE C] then 'NSE_CURRENCY'
      when %i[BSE C] then 'BSE_CURRENCY'
      when %i[MCX M] then 'MCX_COMM'
      else
        raise ArgumentError, "Unsupported exchange and segment combination: #{exchange}, #{segment}"
      end
    end

    # Maps segment code to human-readable name
    # @param segment [String, Symbol] Segment code
    # @return [String] Human-readable segment name
    def self.segment_name(segment)
      case segment.to_s.upcase.to_sym
      when :I then 'Index'
      when :E then 'Equity'
      when :D then 'Derivatives'
      when :C then 'Currency'
      when :M then 'Commodity'
      else
        "Unknown (#{segment})"
      end
    end

    # Maps exchange code to human-readable name
    # @param exchange [String, Symbol] Exchange code
    # @return [String] Human-readable exchange name
    def self.exchange_name(exchange)
      case exchange.to_s.upcase.to_sym
      when :NSE then 'National Stock Exchange'
      when :BSE then 'Bombay Stock Exchange'
      when :MCX then 'Multi Commodity Exchange'
      else
        "Unknown (#{exchange})"
      end
    end

    # Get all supported exchange-segment combinations
    # @return [Array<Array<String>>] Array of [exchange, segment] pairs
    def self.supported_combinations
      [
        %w[NSE I], %w[BSE I],
        %w[NSE E], %w[BSE E],
        %w[NSE D], %w[BSE D],
        %w[NSE C], %w[BSE C],
        %w[MCX M]
      ]
    end

    # Check if an exchange-segment combination is supported
    # @param exchange [String, Symbol] Exchange name
    # @param segment [String, Symbol] Segment code
    # @return [Boolean] True if supported
    def self.supported?(exchange, segment)
      supported_combinations.include?([exchange.to_s.upcase, segment.to_s.upcase])
    end
  end
end
