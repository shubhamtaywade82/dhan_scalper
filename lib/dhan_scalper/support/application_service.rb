# frozen_string_literal: true

module DhanScalper
  # Minimal service base: subclasses implement #call
  class ApplicationService
    def self.call(*args, **kwargs)
      new(*args, **kwargs).call
    end
  end
end

