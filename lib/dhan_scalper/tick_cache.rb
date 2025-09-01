require "concurrent"
module DhanScalper
  class TickCache
    MAP = Concurrent::Map.new
    def self.put(t) = MAP["#{t[:segment]}:#{t[:security_id]}"]=t
    def self.ltp(seg, sid) = MAP["#{seg}:#{sid}"]&.dig(:ltp)
  end
end