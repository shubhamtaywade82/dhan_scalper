# frozen_string_literal: true

module DhanScalper
  module TimeZone
    module_function

    def parse(str_or_num)
      return Time.at(str_or_num.to_i) if str_or_num.is_a?(Numeric)

      begin
        Time.parse(str_or_num.to_s)
      rescue StandardError
        Time.now
      end
    end

    def at(epoch)
      Time.at(epoch.to_i)
    end
  end
end
