# frozen_string_literal: true

require 'json'
require 'fileutils'

module DhanScalper
  module Services
    class HistoricalDataCache
      CACHE_DIR = 'data/cache'
      CACHE_DURATION = 300 # 5 minutes cache duration

      class << self
        def get(seg, sid, interval)
          cache_key = "#{seg}_#{sid}_#{interval}"
          cache_file = File.join(CACHE_DIR, "#{cache_key}.json")

          return nil unless File.exist?(cache_file)
          return nil unless cache_valid?(cache_file)

          begin
            data = JSON.parse(File.read(cache_file))
            puts "[CACHE] Hit for #{cache_key}"
            data
          rescue StandardError => e
            puts "[CACHE] Error reading cache for #{cache_key}: #{e.message}"
            nil
          end
        end

        def set(seg, sid, interval, data)
          cache_key = "#{seg}_#{sid}_#{interval}"
          cache_file = File.join(CACHE_DIR, "#{cache_key}.json")

          FileUtils.mkdir_p(CACHE_DIR)

          begin
            File.write(cache_file, JSON.pretty_generate(data))
            puts "[CACHE] Stored data for #{cache_key}"
          rescue StandardError => e
            puts "[CACHE] Error storing cache for #{cache_key}: #{e.message}"
          end
        end

        def clear
          return unless Dir.exist?(CACHE_DIR)

          FileUtils.rm_rf(CACHE_DIR)
          puts '[CACHE] Cleared all cached data'
        end

        private

        def cache_valid?(cache_file)
          return false unless File.exist?(cache_file)

          (Time.now - File.mtime(cache_file)) < CACHE_DURATION
        end
      end
    end
  end
end
