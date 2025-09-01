# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/bin/"
  add_filter "/exe/"
  add_filter "/.github/"
  minimum_coverage 90
end

require "webmock/rspec"
require "dhan_scalper"
require "fileutils"
require "tempfile"

# Load integration helpers
require_relative "support/integration_helpers"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Configure integration tests
  config.define_derived_metadata(file_path: %r{spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end

  # Global test setup
  config.before(:suite) do
    # Create test data directory
    FileUtils.mkdir_p("test_data")
  end

  config.after(:suite) do
    # Clean up test data
    FileUtils.rm_rf("test_data") if Dir.exist?("test_data")
  end

  # Mock DhanHQ to avoid actual API calls
  config.before(:each) do
    # Create a mock module for DhanHQ
    dhanhq_module = Module.new
    stub_const("DhanHQ", dhanhq_module)

    # Add methods to the module
    allow(DhanHQ).to receive(:configure_with_env)
    allow(DhanHQ).to receive(:logger).and_return(double(level: :info))

    # Mock DhanHQ::Models
    models_module = Module.new
    stub_const("DhanHQ::Models", models_module)

    # Mock Funds class
    funds_class = Class.new
    stub_const("DhanHQ::Models::Funds", funds_class)
    allow(funds_class).to receive(:fetch).and_return(double(
      available_balance: 100000.0,
      utilized_amount: 50000.0
    ))

    # Mock DhanHQ::WS
    ws_module = Module.new
    stub_const("DhanHQ::WS", ws_module)

    # Mock WS::Client class
    ws_client_class = Class.new
    stub_const("DhanHQ::WS::Client", ws_client_class)

    # Mock WebSocket client
    mock_ws = double
    allow(mock_ws).to receive(:on)
    allow(mock_ws).to receive(:subscribe_one)
    allow(mock_ws).to receive(:disconnect!)
    allow(ws_client_class).to receive(:new).and_return(mock_ws)

    # Mock Technical Analysis libraries
    stub_const("TechnicalAnalysis", double)
    allow(TechnicalAnalysis).to receive(:ema).and_return([50.0, 51.0, 52.0])
    allow(TechnicalAnalysis).to receive(:rsi).and_return([45.0, 46.0, 47.0])

    # Mock RubyTechnicalAnalysis
    ruby_ta_module = Module.new
    stub_const("RubyTechnicalAnalysis", ruby_ta_module)

    # Mock Indicator module
    indicator_module = Module.new
    stub_const("RubyTechnicalAnalysis::Indicator", indicator_module)

    # Mock Ema class
    ema_class = Class.new
    stub_const("RubyTechnicalAnalysis::Indicator::Ema", ema_class)
    allow(ema_class).to receive(:new).and_return(double(calculate: [50.0, 51.0, 52.0]))

    # Mock Rsi class
    rsi_class = Class.new
    stub_const("RubyTechnicalAnalysis::Indicator::Rsi", rsi_class)
    allow(rsi_class).to receive(:new).and_return(double(calculate: [45.0, 46.0, 47.0]))
  end
end
