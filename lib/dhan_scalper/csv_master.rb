# frozen_string_literal: true

require "csv"
require "net/http"
require "uri"
require "fileutils"

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
        .select { |row|
          row["UNDERLYING_SYMBOL"] == underlying_symbol &&
          ["OPTFUT", "OPTIDX"].include?(row["INSTRUMENT"])
        }
        .map { |row| row["SM_EXPIRY_DATE"] }
        .compact
        .uniq
        .sort

      puts "[CSV_MASTER] Found #{expiries.length} expiry dates for #{underlying_symbol}: #{expiries.join(', ')}"
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
        ["OPTFUT", "OPTIDX"].include?(row["INSTRUMENT"]) &&
        row["SM_EXPIRY_DATE"] == expiry_date &&
        row["STRIKE_PRICE"].to_f == strike_price &&
        row["OPTION_TYPE"] == option_type
      end

      if security
        puts "[CSV_MASTER] Found security ID #{security['SECURITY_ID']} for #{underlying_symbol} #{expiry_date} #{strike_price} #{option_type}"
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
        .select { |row|
          row["UNDERLYING_SYMBOL"] == underlying_symbol &&
          ["OPTFUT", "OPTIDX"].include?(row["INSTRUMENT"]) &&
          row["SM_EXPIRY_DATE"] == expiry_date
        }
        .map { |row| row["STRIKE_PRICE"].to_f }
        .compact
        .uniq
        .sort

      puts "[CSV_MASTER] Found #{strikes.length} strikes for #{underlying_symbol} #{expiry_date}"
      strikes
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
      @data = CSV.read(CACHE_FILE, headers: true)
      @last_fetch = File.mtime(CACHE_FILE)
      puts "[CSV_MASTER] Loaded #{@data.length} records from cache"
    rescue => e
      puts "[CSV_MASTER] Failed to load from cache: #{e.message}"
      fetch_and_cache
    end

    def fetch_and_cache
      puts "[CSV_MASTER] Fetching fresh data from: #{CSV_URL}"

      begin
        uri = URI(CSV_URL)
        response = Net::HTTP.get_response(uri)

        unless response.is_a?(Net::HTTPSuccess)
          raise "HTTP error: #{response.code} #{response.message}"
        end

        # Ensure cache directory exists
        FileUtils.mkdir_p(CACHE_DIR)

        # Write to cache file
        File.write(CACHE_FILE, response.body)

        # Load the data
        @data = CSV.parse(response.body, headers: true)
        @last_fetch = Time.now

        puts "[CSV_MASTER] Successfully fetched and cached #{@data.length} records"

      rescue => e
        puts "[CSV_MASTER] Failed to fetch data: #{e.message}"

        # Try to load from cache even if it's stale
        if File.exist?(CACHE_FILE)
          puts "[CSV_MASTER] Falling back to stale cache"
          load_from_cache
        else
          raise "Unable to fetch CSV master data and no cache available"
        end
      end
    end
  end
end
