# frozen_string_literal: true

require_relative '../services/dhanhq_config'

module DhanScalper
  module Services
    # LTP fallback service using DhanHQ MarketFeed API
    # Used when WebSocket is not connected or instrument is not subscribed
    # Note: MarketFeed LTP API only returns last_price, other fields are set to nil
    class LtpFallback
      attr_reader :logger, :cache, :cache_ttl

      def initialize(logger: nil, cache: nil, cache_ttl: 30)
        @logger = logger || Logger.new($stdout)
        @cache = cache || {}
        @cache_ttl = cache_ttl
      end

      # Get LTP for a single instrument
      # @param segment [String] Exchange segment (e.g., "NSE_EQ", "NSE_FO", "IDX_I")
      # @param security_id [String] Security ID
      # @return [Hash, nil] Tick data with ltp, ts (other fields set to nil as API doesn't provide them)
      def get_ltp(segment, security_id)
        cache_key = "#{segment}:#{security_id}"

        # Check cache first
        cached_data = @cache[cache_key]
        if cached_data && (Time.now - cached_data[:timestamp]) < @cache_ttl
          @logger.debug "[LTP_FALLBACK] Using cached data for #{segment}:#{security_id}"
          return cached_data[:data]
        end

        # Fetch from API
        fetch_ltp_from_api(segment, security_id)
      end

      # Get LTP for multiple instruments
      # @param instruments [Array<Hash>] Array of {segment:, security_id:} hashes
      # @return [Hash] Hash with "#{segment}:#{security_id}" as keys
      def get_multiple_ltp(instruments)
        return {} if instruments.empty?

        # Group by segment for batch API calls
        segments = instruments.group_by { |inst| inst[:segment] }
        results = {}

        segments.each do |segment, segment_instruments|
          security_ids = segment_instruments.map { |inst| inst[:security_id] }

          begin
            segment_data = fetch_segment_ltp(segment, security_ids)
            segment_data.each do |security_id, tick_data|
              key = "#{segment}:#{security_id}"
              results[key] = tick_data

              # Cache the result
              cache_key = "#{segment}:#{security_id}"
              @cache[cache_key] = {
                data: tick_data,
                timestamp: Time.now
              }
            end
          rescue StandardError => e
            @logger.warn "[LTP_FALLBACK] Failed to fetch #{segment}: #{e.message}"
            # Set nil for failed instruments
            security_ids.each do |security_id|
              key = "#{segment}:#{security_id}"
              results[key] = nil
            end
          end
        end

        results
      end

      # Check if LTP is available (cached or can be fetched)
      # @param segment [String] Exchange segment
      # @param security_id [String] Security ID
      # @return [Boolean] True if LTP is available
      def available?(segment, security_id)
        cache_key = "#{segment}:#{security_id}"

        # Check cache
        cached_data = @cache[cache_key]
        return true if cached_data && (Time.now - cached_data[:timestamp]) < @cache_ttl

        # Check if we can fetch from API
        DhanScalper::Services::DhanHQConfig.configured?
      end

      # Clear cache
      def clear_cache
        @cache.clear
        @logger.debug '[LTP_FALLBACK] Cache cleared'
      end

      # Get cache statistics
      def cache_stats
        {
          size: @cache.size,
          keys: @cache.keys,
          ttl: @cache_ttl
        }
      end

      private

      # Fetch LTP for a single instrument from API
      def fetch_ltp_from_api(segment, security_id)
        @logger.debug "[LTP_FALLBACK] Fetching LTP for #{segment}:#{security_id}"

        begin
          # Ensure DhanHQ is configured
          DhanScalper::Services::DhanHQConfig.validate!

          # Prepare parameters for MarketFeed.ltp
          params = { segment => [security_id.to_i] }

          # Call DhanHQ MarketFeed API
          response = DhanHQ::Models::MarketFeed.ltp(params)

          if response && response['status'] == 'success' && response['data']
            segment_data = response['data'][segment]
            if segment_data && segment_data[security_id.to_s]
              instrument_data = segment_data[security_id.to_s]

              tick_data = {
                ltp: instrument_data['last_price']&.to_f,
                ts: Time.now.to_i,
                day_high: nil, # MarketFeed LTP API doesn't provide day_high
                day_low: nil,  # MarketFeed LTP API doesn't provide day_low
                atp: nil,      # MarketFeed LTP API doesn't provide average_price
                vol: nil,      # MarketFeed LTP API doesn't provide volume
                segment: segment,
                security_id: security_id
              }

              # Cache the result
              cache_key = "#{segment}:#{security_id}"
              @cache[cache_key] = {
                data: tick_data,
                timestamp: Time.now
              }

              @logger.debug "[LTP_FALLBACK] Successfully fetched LTP: #{tick_data[:ltp]}"
              return tick_data
            end
          end

          @logger.warn "[LTP_FALLBACK] No data returned for #{segment}:#{security_id}"
          nil
        rescue StandardError => e
          @logger.error "[LTP_FALLBACK] Failed to fetch LTP for #{segment}:#{security_id}: #{e.message}"
          nil
        end
      end

      # Fetch LTP for multiple instruments in a segment
      def fetch_segment_ltp(segment, security_ids)
        @logger.debug "[LTP_FALLBACK] Fetching LTP for #{segment}: #{security_ids.join(', ')}"

        begin
          # Ensure DhanHQ is configured
          DhanScalper::Services::DhanHQConfig.validate!

          # Prepare parameters for MarketFeed.ltp
          params = { segment => security_ids.map(&:to_i) }

          # Call DhanHQ MarketFeed API
          response = DhanHQ::Models::MarketFeed.ltp(params)

          if response && response['status'] == 'success' && response['data']
            segment_data = response['data'][segment]
            results = {}

            security_ids.each do |security_id|
              if segment_data && segment_data[security_id.to_s]
                instrument_data = segment_data[security_id.to_s]

                tick_data = {
                  ltp: instrument_data['last_price']&.to_f,
                  ts: Time.now.to_i,
                  day_high: nil, # MarketFeed LTP API doesn't provide day_high
                  day_low: nil,  # MarketFeed LTP API doesn't provide day_low
                  atp: nil,      # MarketFeed LTP API doesn't provide average_price
                  vol: nil,      # MarketFeed LTP API doesn't provide volume
                  segment: segment,
                  security_id: security_id
                }

                results[security_id] = tick_data

                # Cache the result
                cache_key = "#{segment}:#{security_id}"
                @cache[cache_key] = {
                  data: tick_data,
                  timestamp: Time.now
                }
              else
                results[security_id] = nil
              end
            end

            @logger.debug "[LTP_FALLBACK] Successfully fetched #{results.size} LTPs for #{segment}"
            return results
          end

          @logger.warn "[LTP_FALLBACK] No data returned for #{segment}"
          {}
        rescue StandardError => e
          @logger.error "[LTP_FALLBACK] Failed to fetch LTP for #{segment}: #{e.message}"
          {}
        end
      end
    end
  end
end
