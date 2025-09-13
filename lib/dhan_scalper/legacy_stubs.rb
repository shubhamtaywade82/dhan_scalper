# frozen_string_literal: true

module DhanScalper
  # Deprecated placeholder for legacy TrendEngine
  # Retained to avoid breaking external references and tests.
  class TrendEngine
    def initialize(*) = nil
    def call(*) = nil
  end

  # Deprecated UI namespace placeholders
  module UI
    class Dashboard
      def initialize(*) = nil
    end

    class DataViewer
      def initialize(*) = nil
    end
  end

  # Deprecated App constant (legacy). Not used by current CLI.
  class App
    def initialize(*) = nil
  end
end
