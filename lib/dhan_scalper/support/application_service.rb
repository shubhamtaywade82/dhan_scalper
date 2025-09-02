# frozen_string_literal: true

module DhanScalper
  # Minimal service base: subclasses implement #call
  class ApplicationService
    def self.call(*, **)
      new(*, **).call
    end
  end
end
