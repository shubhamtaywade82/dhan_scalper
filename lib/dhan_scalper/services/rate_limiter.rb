# frozen_string_literal: true

module DhanScalper
  module Services
    class RateLimiter
      class << self
        def last_request_time
          @last_request_time ||= {}
        end

        def min_interval
          @min_interval ||= 60 # 1 minute in seconds
        end

        def can_make_request?(key)
          last_time = last_request_time[key]
          return true unless last_time

          (Time.now - last_time) >= min_interval
        end

        def record_request(key)
          last_request_time[key] = Time.now
        end

        def wait_if_needed(key)
          return unless last_request_time[key]

          time_since_last = Time.now - last_request_time[key]
          if time_since_last < min_interval
            wait_time = min_interval - time_since_last
            puts "[RATE_LIMITER] Waiting #{wait_time.round(1)}s before next request for #{key}"
            sleep(wait_time)
          end
        end

        def time_until_next_request(key)
          return 0 unless last_request_time[key]

          time_since_last = Time.now - last_request_time[key]
          [min_interval - time_since_last, 0].max
        end
      end
    end
  end
end
