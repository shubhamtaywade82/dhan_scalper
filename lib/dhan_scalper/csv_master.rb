# frozen_string_literal: true

require "csv"
require "net/http"
require "uri"
require "fileutils"
require "timeout"
require_relative "exchange_segment_mapper"

module DhanScalper
  class CsvMaster
    CSV_URL = "https://images.dhan.co/api-data/api-scrip-master-detailed.csv"
    CACHE_DIR = File.expand_path("~/.dhan_scalper/cache")
    CACHE_FILE = File.join(CACHE_DIR, "api-scrip-master-detailed.csv")
    CACHE_DURATION = 24 * 60 * 60 # 24 hours in seconds

    def initialize
      @data = nil
      @last_fetch = nil
    end

    # Get all available expiry dates for a given underlying symbol
    def get_expiry_dates(underlying_symbol)
      ensure_data_loaded
      return [] unless @data

      # Look for both OPTFUT and OPTIDX instruments
      expiries = @data
                 .select do |row|
        row["UNDERLYING_SYMBOL"] == underlying_symbol &&
          %w[OPTFUT OPTIDX].include?(row["INSTRUMENT"])
      end
        .filter_map { |row| row["SM_EXPIRY_DATE"] }
                 .uniq
                 .sort

      puts "[CSV_MASTER] Found #{expiries.length} expiry dates for #{underlying_symbol}: #{expiries.join(", ")}"
      expiries
    end

    # Get security ID for a specific option
    def get_security_id(underlying_symbol, expiry_date, strike_price, option_type)
      ensure_data_loaded
      return nil unless @data

      option_type = option_type.upcase
      strike_price = strike_price.to_f

      security = @data.find do |row|
        row["UNDERLYING_SYMBOL"] == underlying_symbol &&
          %w[OPTFUT OPTIDX].include?(row["INSTRUMENT"]) &&
          row["SM_EXPIRY_DATE"] == expiry_date &&
          row["STRIKE_PRICE"].to_f == strike_price &&
          row["OPTION_TYPE"] == option_type
      end

      if security
        puts "[CSV_MASTER] Found security ID #{security["SECURITY_ID"]} for #{underlying_symbol} #{expiry_date} #{strike_price} #{option_type}"
        security["SECURITY_ID"]
      else
        puts "[CSV_MASTER] No security found for #{underlying_symbol} #{expiry_date} #{strike_price} #{option_type}"
        nil
      end
    end

    # Get lot size for a security
    def get_lot_size(security_id)
      ensure_data_loaded
      return nil unless @data

      security = @data.find { |row| row["SECURITY_ID"] == security_id }
      security ? security["LOT_SIZE"].to_i : nil
    end

    # Get all available strikes for a given underlying and expiry
    def get_available_strikes(underlying_symbol, expiry_date)
      ensure_data_loaded
      return [] unless @data

      strikes = @data
                .select do |row|
        row["UNDERLYING_SYMBOL"] == underlying_symbol &&
          %w[OPTFUT OPTIDX].include?(row["INSTRUMENT"]) &&
          row["SM_EXPIRY_DATE"] == expiry_date
      end
        .filter_map { |row| row["STRIKE_PRICE"].to_f }
                .uniq
                .sort

      puts "[CSV_MASTER] Found #{strikes.length} strikes for #{underlying_symbol} #{expiry_date}"
      strikes
    end

    # Get exchange segment for a specific security ID
    # @param security_id [String] Security ID to look up
    # @param exchange [String, nil] Optional exchange filter (e.g., "NSE", "BSE", "MCX")
    # @param segment [String, nil] Optional segment filter (e.g., "I", "E", "D", "C", "M")
    # @return [String, nil] DhanHQ exchange segment code or nil if not found
    def get_exchange_segment(security_id, exchange: nil, segment: nil)
      ensure_data_loaded
      return nil unless @data

      # Find security with optional exchange and segment filters
      security = @data.find do |row|
        matches = row["SECURITY_ID"] == security_id
        matches &&= row["EXCH_ID"] == exchange if exchange
        matches &&= row["SEGMENT"] == segment if segment
        matches
      end
      return nil unless security

      exchange = security["EXCH_ID"]
      segment = security["SEGMENT"]

      begin
        DhanScalper::ExchangeSegmentMapper.exchange_segment(exchange, segment)
      rescue ArgumentError => e
        puts "[CSV_MASTER] Warning: #{e.message} for security_id #{security_id}"
        nil
      end
    end

    # Get exchange segment for a specific underlying symbol and instrument type
    # @param underlying_symbol [String] Underlying symbol (e.g., "NIFTY")
    # @param instrument_type [String] Instrument type (e.g., "OPTIDX", "OPTFUT")
    # @return [String, nil] DhanHQ exchange segment code or nil if not found
    def get_exchange_segment_by_symbol(underlying_symbol, instrument_type = "OPTIDX")
      ensure_data_loaded
      return nil unless @data

      security = @data.find do |row|
        row["UNDERLYING_SYMBOL"] == underlying_symbol &&
          row["INSTRUMENT"] == instrument_type
      end
      return nil unless security

      exchange = security["EXCH_ID"]
      segment = security["SEGMENT"]

      begin
        DhanScalper::ExchangeSegmentMapper.exchange_segment(exchange, segment)
      rescue ArgumentError => e
        puts "[CSV_MASTER] Warning: #{e.message} for #{underlying_symbol} #{instrument_type}"
        nil
      end
    end

    # Get all instruments with their exchange segments
    # @param underlying_symbol [String, nil] Filter by underlying symbol (optional)
    # @param symbols [Array<String>, nil] Filter by multiple symbols (optional)
    # @return [Array<Hash>] Array of hashes with security info and exchange segment
    def get_instruments_with_segments(underlying_symbol = nil, symbols = nil)
      ensure_data_loaded
      return [] unless @data

      puts "[CSV_MASTER] Processing #{@data.length} records..."

      # Filter symbols if provided
      target_symbols = if symbols && !symbols.empty?
                         symbols
                       elsif underlying_symbol
                         [underlying_symbol]
                       end

      instruments = []
      processed = 0
      total = @data.length
      last_progress = Time.now

      @data.each do |row|
        processed += 1

        # Show progress every 10,000 records or every 5 seconds
        if processed % 10_000 == 0 || Time.now - last_progress > 5
          progress = (processed.to_f / total * 100).round(1)
          puts "[CSV_MASTER] Progress: #{processed}/#{total} (#{progress}%)"
          last_progress = Time.now
        end

        # Skip if filtering by symbol and this row doesn't match
        next if target_symbols && !target_symbols.include?(row["UNDERLYING_SYMBOL"])

        # Skip if filtering by single symbol and this row doesn't match
        next if underlying_symbol && row["UNDERLYING_SYMBOL"] != underlying_symbol

        exchange = row["EXCH_ID"]
        segment = row["SEGMENT"]

        exchange_segment = begin
          DhanScalper::ExchangeSegmentMapper.exchange_segment(exchange, segment)
        rescue ArgumentError
          nil
        end

        instruments << {
          security_id: row["SECURITY_ID"],
          underlying_symbol: row["UNDERLYING_SYMBOL"],
          symbol_name: row["SYMBOL_NAME"],
          instrument: row["INSTRUMENT"],
          exchange: exchange,
          segment: segment,
          exchange_segment: exchange_segment,
          lot_size: row["LOT_SIZE"].to_i,
          strike_price: row["STRIKE_PRICE"],
          option_type: row["OPTION_TYPE"],
          expiry_date: row["SM_EXPIRY_DATE"],
        }
      end

      puts "[CSV_MASTER] Processed #{processed} records, found #{instruments.length} matching instruments"
      instruments
    end

    # Get instruments for specific symbols with caching
    # @param symbols [Array<String>] Array of symbol names to filter
    # @param redis_store [DhanScalper::Stores::RedisStore, nil] Optional Redis store for caching
    # @return [Hash] Hash with symbol as key and array of instruments as value
    def get_instruments_for_symbols(symbols, redis_store = nil)
      return {} if symbols.empty?

      # Check cache first if Redis store is available
      if redis_store
        cached_result = redis_store.get_cached_instruments(symbols)
        if cached_result
          puts "[CSV_MASTER] Using cached instruments for #{symbols.join(", ")}"
          return cached_result
        end
      end

      puts "[CSV_MASTER] Loading instruments for symbols: #{symbols.join(", ")}"

      # Use optimized filtering
      instruments = get_instruments_with_segments(nil, symbols)

      # Group by symbol
      result = {}
      symbols.each { |symbol| result[symbol] = [] }

      instruments.each do |instrument|
        symbol = instrument[:underlying_symbol]
        result[symbol] << instrument if result[symbol]
      end

      # Cache the result if Redis store is available
      if redis_store
        redis_store.cache_instruments(symbols, result)
        puts "[CSV_MASTER] Cached instruments for #{symbols.join(", ")}"
      end

      result
    end

    # Get exchange and segment info for a security
    # @param security_id [String] Security ID to look up
    # @return [Hash, nil] Hash with exchange and segment info or nil if not found
    def get_exchange_info(security_id)
      ensure_data_loaded
      return nil unless @data

      security = @data.find { |row| row["SECURITY_ID"] == security_id }
      return nil unless security

      exchange = security["EXCH_ID"]
      segment = security["SEGMENT"]

      {
        exchange: exchange,
        segment: segment,
        exchange_name: DhanScalper::ExchangeSegmentMapper.exchange_name(exchange),
        segment_name: DhanScalper::ExchangeSegmentMapper.segment_name(segment),
        exchange_segment: begin
          DhanScalper::ExchangeSegmentMapper.exchange_segment(exchange, segment)
        rescue ArgumentError
          nil
        end,
      }
    end

    private

    def ensure_data_loaded
      return if @data && cache_valid?

      if cache_valid?
        load_from_cache
      else
        fetch_and_cache
      end
    end

    def cache_valid?
      return false unless File.exist?(CACHE_FILE)

      @last_fetch ||= File.mtime(CACHE_FILE)
      (Time.now - @last_fetch) < CACHE_DURATION
    end

    def load_from_cache
      puts "[CSV_MASTER] Loading data from cache: #{CACHE_FILE}"

      # Add timeout for CSV loading
      Timeout.timeout(30) do
        @data = CSV.read(CACHE_FILE, headers: true)
        @last_fetch = File.mtime(CACHE_FILE)
        puts "[CSV_MASTER] Loaded #{@data.length} records from cache"
      end
    rescue Timeout::Error
      puts "[CSV_MASTER] Timeout loading CSV from cache, fetching fresh data"
      fetch_and_cache
    rescue StandardError => e
      puts "[CSV_MASTER] Failed to load from cache: #{e.message}"
      fetch_and_cache
    end

    def fetch_and_cache
      puts "[CSV_MASTER] Fetching fresh data from: #{CSV_URL}"

      begin
        uri = URI(CSV_URL)
        response = Net::HTTP.get_response(uri)

        raise "HTTP error: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        # Ensure cache directory exists
        FileUtils.mkdir_p(CACHE_DIR)

        # Write to cache file
        File.write(CACHE_FILE, response.body)

        # Load the data
        @data = CSV.parse(response.body, headers: true)
        @last_fetch = Time.now

        puts "[CSV_MASTER] Successfully fetched and cached #{@data.length} records"
      rescue StandardError => e
        puts "[CSV_MASTER] Failed to fetch data: #{e.message}"

        # Try to load from cache even if it's stale
        raise "Unable to fetch CSV master data and no cache available" unless File.exist?(CACHE_FILE)

        puts "[CSV_MASTER] Falling back to stale cache"
        load_from_cache
      end
    end
  end
end
