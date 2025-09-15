# frozen_string_literal: true

module DhanScalper
  module Support
    # Normalizes various inbound tick payload shapes into a canonical TickCache format.
    # Canonical keys:
    # - segment, security_id, ltp, open, high, low, close, volume, ts
    # - day_high, day_low, atp, vol, kind (optional)
    # - instrument_type, expiry_date, strike_price, option_type (for F&O)
    class TickNormalizer
      class << self
        def normalize(payload, overrides = {})
          return nil unless payload.is_a?(Hash)

          h = symbolize_keys(payload.dup)

          # Debug logging (can be disabled in production)
          puts "Payload: #{payload.inspect}" if ENV['DHAN_LOG_LEVEL'] == 'DEBUG'

          # Check if this is a quote packet - only quote packets get full normalization
          if h[:kind] == :quote
            # Full normalization for quote packets
            instrument_type = detect_instrument_type(h, overrides)
            segment = determine_segment(h, overrides, instrument_type)

            # Field mapping based on instrument type
            normalized = case instrument_type
                         when :index
                           normalize_index_payload(h, overrides, segment)
                         when :nse_fno
                           normalize_nse_fno_payload(h, overrides, segment)
                         when :bse_fno
                           normalize_bse_fno_payload(h, overrides, segment)
                         when :equity
                           normalize_equity_payload(h, overrides, segment)
                         else
                           normalize_generic_payload(h, overrides, segment)
                         end

            return nil unless normalized && normalized[:segment] && normalized[:security_id]

            # Preserve any extra fields that might be useful later
            extras = h.reject { |k, _| normalized.key?(k) }
            normalized.merge!(extras) if extras.any?

            normalized
          else
            # For non-quote packets (OI, etc.), return the raw data for merging
            # This allows the caller to merge additional data into existing normalized data
            h
          end
        end

        private

        def detect_instrument_type(payload, overrides)
          # Check for explicit instrument type in overrides
          return overrides[:instrument_type] if overrides[:instrument_type]

          # Check for instrument type in payload
          return payload[:instrument_type] if payload[:instrument_type]

          # Infer from segment
          segment = overrides[:segment] || payload[:segment] || payload[:exchange_segment]
          case segment.to_s.upcase
          when 'IDX_I'
            :index
          when 'NSE_FNO', 'NFO'
            :nse_fno
          when 'BSE_FNO', 'BFO'
            :bse_fno
          when 'NSE_EQ', 'BSE_EQ'
            :equity
          else
            :generic
          end
        end

        def determine_segment(payload, overrides, instrument_type)
          # Use overrides first
          return overrides[:segment] if overrides[:segment]

          # Use payload segment
          return payload[:segment] if payload[:segment]
          return payload[:exchange_segment] if payload[:exchange_segment]

          # Default based on instrument type
          case instrument_type
          when :index
            'IDX_I'
          when :nse_fno
            'NSE_FNO'
          when :bse_fno
            'BSE_FNO'
          when :equity
            'NSE_EQ'
          else
            'NSE_FNO' # Default fallback
          end
        end

        def normalize_index_payload(h, overrides, segment)
          # Index instruments (NIFTY, BANKNIFTY, SENSEX)
          # DhanHQ WebSocket fields: security_id, ltp, ts, day_high, day_low, atp, vol, segment
          {
            segment: segment,
            security_id: overrides[:security_id] || h[:security_id] || h[:instrument_id] || h[:sid],
            ltp: numeric(overrides[:ltp] || h[:ltp] || h[:last_price] || h[:price]),
            open: numeric(overrides[:open] || h[:open]),
            high: numeric(overrides[:high] || h[:high]),
            low: numeric(overrides[:low] || h[:low]),
            close: numeric(overrides[:close] || h[:close]),
            volume: integer(overrides[:volume] || h[:volume] || h[:vol]),
            ts: integer(overrides[:ts] || h[:ts] || h[:timestamp]),
            day_high: numeric(overrides[:day_high] || h[:day_high] || h[:high]),
            day_low: numeric(overrides[:day_low] || h[:day_low] || h[:low]),
            atp: numeric(overrides[:atp] || h[:atp] || h[:ltp] || h[:last_price]),
            vol: integer(overrides[:vol] || h[:vol] || h[:volume]),
            instrument_type: 'INDEX'
          }
        end

        def normalize_nse_fno_payload(h, overrides, segment)
          # NSE Futures and Options
          # Additional fields: expiry_date, strike_price, option_type, lot_size
          base = normalize_index_payload(h, overrides, segment)
          base.merge({
                       instrument_type: 'OPTION', # or "FUTURE" based on payload
                       expiry_date: h[:expiry_date] || h[:expiry],
                       strike_price: numeric(h[:strike_price] || h[:strike]),
                       option_type: h[:option_type] || h[:opt_type],
                       lot_size: integer(h[:lot_size] || h[:lot]),
                       tick_size: numeric(h[:tick_size] || h[:tick]),
                       underlying: h[:underlying] || h[:underlying_symbol]
                     })
        end

        def normalize_bse_fno_payload(h, overrides, segment)
          # BSE Futures and Options (similar to NSE but with BSE-specific fields)
          base = normalize_nse_fno_payload(h, overrides, segment)
          base.merge({
                       exchange: 'BSE',
                       # BSE might have different field names or additional fields
                       bse_instrument_id: h[:bse_instrument_id] || h[:bse_id]
                     })
        end

        def normalize_equity_payload(h, overrides, segment)
          # Equity instruments
          base = normalize_index_payload(h, overrides, segment)
          base.merge({
                       instrument_type: 'EQUITY',
                       symbol: h[:symbol] || h[:trading_symbol],
                       company_name: h[:company_name] || h[:name],
                       isin: h[:isin]
                     })
        end

        def normalize_generic_payload(h, overrides, segment)
          # Generic fallback for unknown instrument types
          normalize_index_payload(h, overrides, segment)
        end

        def symbolize_keys(hash)
          hash.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }
        end

        def numeric(value)
          return nil if value.nil?
          return value if value.is_a?(Numeric)

          s = value.to_s
          s.include?('.') ? s.to_f : s.to_i
        rescue StandardError
          nil
        end

        def integer(value)
          return nil if value.nil?
          return value.to_i if value.is_a?(Numeric) || value.is_a?(String)

          nil
        rescue StandardError
          nil
        end
      end
    end
  end
end
