# frozen_string_literal: true

module IntegrationHelpers
  # Helper method to capture stdout for testing CLI output
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  # Helper method to capture stderr for testing error output
  def capture_stderr
    old_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old_stderr
  end

  # Helper method to create a test configuration
  def create_test_config(overrides = {})
    {
      "global" => {
        "min_profit_target" => 1000,
        "max_day_loss" => 1500,
        "charge_per_order" => 20,
        "allocation_pct" => 0.30,
        "slippage_buffer_pct" => 0.01,
        "max_lots_per_trade" => 10,
        "decision_interval" => 10,
        "log_level" => "INFO",
        "tp_pct" => 0.35,
        "sl_pct" => 0.18,
        "trail_pct" => 0.12
      },
      "paper" => {
        "starting_balance" => 200_000
      },
      "SYMBOLS" => {
        "NIFTY" => {
          "idx_sid" => "13",
          "seg_idx" => "IDX_I",
          "seg_opt" => "NSE_FNO",
          "strike_step" => 50,
          "lot_size" => 75,
          "qty_multiplier" => 1,
          "expiry_wday" => 4
        }
      }
    }.deep_merge(overrides)
  end

  # Helper method to create a mock CSV master for testing
  def create_mock_csv_master
    mock_master = double("CsvMaster")

    # Mock expiry dates
    allow(mock_master).to receive(:get_expiry_dates).with("NIFTY").and_return([
      "2025-09-02", "2025-09-09", "2025-09-16", "2025-09-23", "2025-09-30"
    ])

    # Mock security ID lookups
    allow(mock_master).to receive(:get_security_id).with("NIFTY", "2025-09-02", 25000, "CE").and_return("TEST_CE_25000")
    allow(mock_master).to receive(:get_security_id).with("NIFTY", "2025-09-02", 25000, "PE").and_return("TEST_PE_25000")
    allow(mock_master).to receive(:get_security_id).with("NIFTY", "2025-09-02", 24950, "CE").and_return("TEST_CE_24950")
    allow(mock_master).to receive(:get_security_id).with("NIFTY", "2025-09-02", 24950, "PE").and_return("TEST_PE_24950")
    allow(mock_master).to receive(:get_security_id).with("NIFTY", "2025-09-02", 25050, "CE").and_return("TEST_CE_25050")
    allow(mock_master).to receive(:get_security_id).with("NIFTY", "2025-09-02", 25050, "PE").and_return("TEST_PE_25050")

    # Mock lot size
    allow(mock_master).to receive(:get_lot_size).and_return(75)

    mock_master
  end

  # Helper method to create a mock tick cache
  def create_mock_tick_cache
    allow(DhanScalper::TickCache).to receive(:ltp).and_return(100.0)
  end

  # Helper method to wait for a condition with timeout
  def wait_for_condition(timeout: 10, interval: 0.1)
    start_time = Time.now

    loop do
      result = yield
      return result if result

      if Time.now - start_time > timeout
        raise "Condition not met within #{timeout} seconds"
      end

      sleep(interval)
    end
  end

  # Helper method to create a test order
  def create_test_order(security_id: "TEST123", side: "BUY", quantity: 100, price: 100.0)
    DhanScalper::Order.new(
      "TEST_ORDER_#{Time.now.to_f}",
      security_id,
      side,
      quantity,
      price
    )
  end

  # Helper method to create a test position
  def create_test_position(symbol: "NIFTY", security_id: "TEST123", side: "BUY", quantity: 100, price: 100.0)
    order = create_test_order(security_id: security_id, side: side, quantity: quantity, price: price)
    DhanScalper::Position.new(order)
  end

  # Helper method to suppress logging during tests
  def suppress_logging
    allow_any_instance_of(Logger).to receive(:info)
    allow_any_instance_of(Logger).to receive(:warn)
    allow_any_instance_of(Logger).to receive(:error)
    allow_any_instance_of(Logger).to receive(:debug)
  end

  # Helper method to restore logging after tests
  def restore_logging
    # Reset any logging mocks
    RSpec::Mocks.space.proxy_for(Logger).reset
  end

  # Helper method to test CSV master data quality
  def validate_csv_data_quality(data)
    # Check for required fields
    required_fields = ["UNDERLYING_SYMBOL", "INSTRUMENT", "SM_EXPIRY_DATE", "STRIKE_PRICE", "OPTION_TYPE", "SECURITY_ID"]

    required_fields.each do |field|
      missing_count = data.count { |r| r[field].nil? || r[field].to_s.strip.empty? }
      expect(missing_count).to be < data.length * 0.1, "#{field} has too many missing values"
    end

    # Check for valid expiry dates
    expiry_dates = data.map { |r| r["SM_EXPIRY_DATE"] }.compact.uniq
    valid_dates = expiry_dates.select { |d| d.match?(/\d{4}-\d{2}-\d{2}/) }
    expect(valid_dates.length).to be > 0, "No valid expiry dates found"

    # Check for unique security IDs
    security_ids = data.map { |r| r["SECURITY_ID"] }.compact
    unique_ids = security_ids.uniq
    expect(unique_ids.length).to eq(security_ids.length), "Security IDs are not unique"
  end

  # Helper method to test option picker with real data
  def test_option_picker_with_real_data(picker, symbol_config)
    # Test expiry fetching
    expiry = picker.fetch_first_expiry
    expect(expiry).to match(/\d{4}-\d{2}-\d{2}/), "Invalid expiry date format"

    # Test option picking
    current_spot = 25000
    options = picker.pick(current_spot: current_spot)

    expect(options).not_to be_nil, "Options should not be nil"
    expect(options[:expiry]).to eq(expiry), "Expiry should match"
    expect(options[:strikes]).to eq([24950, 25000, 25050]), "Strikes should be correct"

    # Check that we have security IDs for all strikes
    options[:strikes].each do |strike|
      expect(options[:ce_sid][strike]).not_to be_nil, "CE security ID missing for strike #{strike}"
      expect(options[:pe_sid][strike]).not_to be_nil, "PE security ID missing for strike #{strike}"
    end
  end
end

RSpec.configure do |config|
  config.include IntegrationHelpers, type: :integration
end
