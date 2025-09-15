# frozen_string_literal: true

require 'csv'
require 'date'
require_relative '../stores/redis_store'

module DhanScalper
  module Services
    # Export ticks from Redis to CSV
    class ExportService
      def initialize(logger: Logger.new($stdout))
        @logger = logger
      end

      def export_since(date_str)
        since_date, since_ts = parse_date(date_str)

        redis_store = DhanScalper::Stores::RedisStore.new(
          namespace: 'dhan_scalper:v1',
          logger: @logger
        )

        begin
          redis_store.connect

          tick_keys = redis_store.redis.keys("#{redis_store.namespace}:ticks:*")
          tick_data = filter_ticks(redis_store, tick_keys, since_ts)
          tick_data.sort_by! { |t| t[:timestamp] }

          csv_filename = write_csv(since_date, tick_data)
          print_summary(csv_filename, tick_data, since_date)
        rescue StandardError => e
          puts "Error during export: #{e.message}"
          raise
        ensure
          redis_store.disconnect
        end
      end

      private

      def parse_date(date_str)
        [Date.parse(date_str), Date.parse(date_str).to_time.to_i]
      rescue ArgumentError
        raise ArgumentError, 'Invalid date format. Use YYYY-MM-DD'
      end

      def filter_ticks(redis_store, keys, since_ts)
        keys.filter_map do |key|
          info = redis_store.redis.hgetall(key)
          next if info.empty?

          ts = info['ts']&.to_i
          next unless ts && ts >= since_ts

          parts = key.split(':')
          {
            timestamp: Time.at(ts).strftime('%Y-%m-%d %H:%M:%S'),
            segment: parts[-2],
            security_id: parts[-1],
            ltp: info['ltp'],
            day_high: info['day_high'],
            day_low: info['day_low'],
            atp: info['atp'],
            volume: info['vol']
          }
        end
      end

      def write_csv(since_date, ticks)
        filename = "export_#{since_date.strftime('%Y%m%d')}_#{Time.now.strftime('%H%M%S')}.csv"
        CSV.open(filename, 'w') do |csv|
          csv << ['Timestamp', 'Segment', 'Security ID', 'LTP', 'Day High', 'Day Low', 'ATP', 'Volume']
          ticks.each do |t|
            csv << [t[:timestamp], t[:segment], t[:security_id], t[:ltp], t[:day_high], t[:day_low], t[:atp],
                    t[:volume]]
          end
        end
        filename
      end

      def print_summary(file, tick_data, since_date)
        puts 'Export completed:'
        puts "  File: #{file}"
        puts "  Records: #{tick_data.size}"
        puts "  Since: #{since_date.strftime('%Y-%m-%d')}"
        puts "  Period: #{tick_data.first&.dig(:timestamp)} to #{tick_data.last&.dig(:timestamp)}"
      end
    end
  end
end
