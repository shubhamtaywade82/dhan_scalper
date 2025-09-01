# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/lib/dhan_scalper/balance_providers"
  add_filter "/lib/dhan_scalper/brokers"
  add_filter "/lib/dhan_scalper/app.rb"
  add_filter "/lib/dhan_scalper/cli.rb"
  add_filter "/lib/dhan_scalper/virtual_data_manager.rb"
  add_filter "/lib/dhan_scalper/trader.rb"
  add_filter "/lib/dhan_scalper/csv_master.rb"
  add_filter "/lib/dhan_scalper/indicators.rb"
  add_filter "/lib/dhan_scalper/candle.rb"
  add_filter "/lib/dhan_scalper/candle_series.rb"
  add_filter "/lib/dhan_scalper/trend_engine.rb"
  add_filter "/lib/dhan_scalper/support"
  add_filter "/lib/dhan_scalper/ui"
end

require "webmock/rspec"
require "dhan_scalper"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
