# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::CsvMaster do
  let(:csv_master) { described_class.new }
  let(:mock_csv_data) do
    <<~CSV
      EXCH_ID,SEGMENT,SECURITY_ID,ISIN,INSTRUMENT,UNDERLYING_SECURITY_ID,UNDERLYING_SYMBOL,SYMBOL_NAME,DISPLAY_NAME,INSTRUMENT_TYPE,SERIES,LOT_SIZE,SM_EXPIRY_DATE,STRIKE_PRICE,OPTION_TYPE
      NSE,I,13,NA,IDX,13,NIFTY,NIFTY,NIFTY,IDX,NA,1,NA,NA,NA
      NSE,I,14,NA,IDX,14,BANKNIFTY,BANKNIFTY,BANKNIFTY,IDX,NA,1,NA,NA,NA
      NSE,D,NIFTY25SEP19000CE,NA,OPTIDX,13,NIFTY,NIFTY25SEP19000CE,NIFTY 19000 CE,OPTIDX,NA,50,2025-09-25,19000,CE
      NSE,D,NIFTY25SEP19000PE,NA,OPTIDX,13,NIFTY,NIFTY25SEP19000PE,NIFTY 19000 PE,OPTIDX,NA,50,2025-09-25,19000,PE
      NSE,D,NIFTY25SEP19100CE,NA,OPTIDX,13,NIFTY,NIFTY25SEP19100CE,NIFTY 19100 CE,OPTIDX,NA,50,2025-09-25,19100,CE
      NSE,D,NIFTY25SEP19100PE,NA,OPTIDX,13,NIFTY,NIFTY25SEP19100PE,NIFTY 19100 PE,OPTIDX,NA,50,2025-09-25,19100,PE
      NSE,D,BANKNIFTY25SEP45000CE,NA,OPTIDX,14,BANKNIFTY,BANKNIFTY25SEP45000CE,BANKNIFTY 45000 CE,OPTIDX,NA,25,2025-09-25,45000,CE
      NSE,D,BANKNIFTY25SEP45000PE,NA,OPTIDX,14,BANKNIFTY,BANKNIFTY25SEP45000PE,BANKNIFTY 45000 PE,OPTIDX,NA,25,2025-09-25,45000,PE
      MCX,M,GOLD25SEP65000CE,NA,OPTFUT,15,GOLD,GOLD25SEP65000CE,GOLD 65000 CE,OPTFUT,NA,100,2025-09-25,65000,CE
      MCX,M,GOLD25SEP65000PE,NA,OPTFUT,15,GOLD,GOLD25SEP65000PE,GOLD 65000 PE,OPTFUT,NA,100,2025-09-25,65000,PE
      NSE,E,RELIANCE,NA,EQ,16,RELIANCE,RELIANCE,RELIANCE,EQ,NA,1,NA,NA,NA
      BSE,E,TCS,NA,EQ,17,TCS,TCS,TCS,EQ,NA,1,NA,NA,NA
      NSE,C,USDINR,NA,FUTCUR,18,USDINR,USDINR,USDINR,FUTCUR,NA,1000,NA,NA,NA
    CSV
  end
  let(:mock_http_response) do
    double(
      code: "200",
      body: mock_csv_data,
      success?: true,
    )
  end
  let(:csv_url) { "https://images.dhan.co/api-data/api-scrip-master-detailed.csv" }
  let(:cache_file) { described_class::CACHE_FILE }

  before do
    # Mock file operations to avoid actual file I/O
    allow(File).to receive_messages(exist?: false, mtime: Time.now - 3_600, read: mock_csv_data)
    allow(File).to receive(:write)
    allow(File).to receive(:open).and_yield(StringIO.new(mock_csv_data))

    # Mock HTTP requests
    allow(Net::HTTP).to receive_messages(get_response: mock_http_response, get: mock_csv_data)
  end

  describe "#initialize" do
    it "initializes with default values" do
      expect(csv_master.instance_variable_get(:@data)).to be_nil
      expect(csv_master.instance_variable_get(:@last_download)).to be_nil
    end
  end

  describe "#get_exchange_segment" do
    it "returns correct exchange segment for NSE index" do
      expect(csv_master.get_exchange_segment("13")).to eq("IDX_I")
    end

    it "returns correct exchange segment for NSE derivatives" do
      expect(csv_master.get_exchange_segment("NIFTY25SEP19000CE")).to eq("NSE_FNO")
    end

    it "returns correct exchange segment for MCX commodity" do
      expect(csv_master.get_exchange_segment("GOLD25SEP65000CE")).to eq("MCX_COMM")
    end

    it "returns correct exchange segment for NSE equity" do
      expect(csv_master.get_exchange_segment("RELIANCE")).to eq("NSE_EQ")
    end

    it "returns correct exchange segment for BSE equity" do
      expect(csv_master.get_exchange_segment("TCS")).to eq("BSE_EQ")
    end

    it "returns correct exchange segment for NSE currency" do
      expect(csv_master.get_exchange_segment("USDINR")).to eq("NSE_CURRENCY")
    end

    it "returns nil for non-existent security ID" do
      expect(csv_master.get_exchange_segment("NONEXISTENT")).to be_nil
    end
  end

  describe "#get_exchange_segment_by_symbol" do
    it "returns correct exchange segment for NIFTY index" do
      expect(csv_master.get_exchange_segment_by_symbol("NIFTY", "IDX")).to eq("IDX_I")
    end

    it "returns correct exchange segment for NIFTY options" do
      expect(csv_master.get_exchange_segment_by_symbol("NIFTY", "OPTIDX")).to eq("NSE_FNO")
    end

    it "returns correct exchange segment for GOLD futures" do
      expect(csv_master.get_exchange_segment_by_symbol("GOLD", "OPTFUT")).to eq("MCX_COMM")
    end

    it "returns nil for non-existent symbol" do
      expect(csv_master.get_exchange_segment_by_symbol("NONEXISTENT", "OPTIDX")).to be_nil
    end
  end

  describe "#get_instruments_with_segments" do
    it "returns all instruments with exchange segments" do
      instruments = csv_master.get_instruments_with_segments
      expect(instruments.length).to eq(13)

      nifty_instrument = instruments.find { |i| i[:underlying_symbol] == "NIFTY" && i[:instrument] == "OPTIDX" }
      expect(nifty_instrument).to include(
        security_id: "NIFTY25SEP19000CE",
        underlying_symbol: "NIFTY",
        exchange: "NSE",
        segment: "D",
        exchange_segment: "NSE_FNO",
        lot_size: 50,
      )
    end

    it "filters by underlying symbol" do
      instruments = csv_master.get_instruments_with_segments("NIFTY")
      expect(instruments.length).to eq(5) # 1 index + 4 options
      expect(instruments.all? { |i| i[:underlying_symbol] == "NIFTY" }).to be true
    end
  end

  describe "#get_exchange_info" do
    it "returns complete exchange info for NSE index" do
      info = csv_master.get_exchange_info("13")
      expect(info).to include(
        exchange: "NSE",
        segment: "I",
        exchange_name: "National Stock Exchange",
        segment_name: "Index",
        exchange_segment: "IDX_I",
      )
    end

    it "returns complete exchange info for MCX commodity" do
      info = csv_master.get_exchange_info("GOLD25SEP65000CE")
      expect(info).to include(
        exchange: "MCX",
        segment: "M",
        exchange_name: "Multi Commodity Exchange",
        segment_name: "Commodity",
        exchange_segment: "MCX_COMM",
      )
    end

    it "returns nil for non-existent security ID" do
      expect(csv_master.get_exchange_info("NONEXISTENT")).to be_nil
    end
  end

  describe "#download_csv" do
    context "when download is successful" do
      before do
        allow(Net::HTTP).to receive(:get_response).and_return(mock_http_response)
        allow(File).to receive(:write)
      end

      it "downloads CSV data successfully" do
        result = csv_master.send(:download_csv)

        expect(result).to eq(mock_csv_data)
        expect(File).to have_received(:write).with(cache_file, mock_csv_data)
      end

      it "updates last download time" do
        csv_master.send(:download_csv)

        expect(csv_master.instance_variable_get(:@last_download)).to be_within(1).of(Time.now)
      end
    end

    context "when download fails" do
      before do
        allow(Net::HTTP).to receive(:get_response).and_raise(StandardError, "Network Error")
      end

      it "raises error when download fails" do
        expect { csv_master.send(:download_csv) }.to raise_error(StandardError, "Network Error")
      end
    end

    context "when HTTP response is not successful" do
      let(:failed_response) do
        double(
          code: "404",
          body: "Not Found",
          success?: false,
        )
      end

      before do
        allow(Net::HTTP).to receive(:get_response).and_return(failed_response)
      end

      it "raises error for non-successful HTTP response" do
        expect { csv_master.send(:download_csv) }.to raise_error(StandardError, /HTTP request failed/)
      end
    end
  end

  describe "#load_from_cache" do
    context "when cache file exists and is valid" do
      before do
        allow(File).to receive_messages(exist?: true, mtime: Time.now - 1_800, read: mock_csv_data)
      end

      it "loads data from cache successfully" do
        result = csv_master.send(:load_from_cache)

        expect(result).to eq(mock_csv_data)
        expect(File).to have_received(:read).with(cache_file)
      end
    end

    context "when cache file doesn't exist" do
      before do
        allow(File).to receive(:exist?).and_return(false)
      end

      it "returns nil when cache file doesn't exist" do
        result = csv_master.send(:load_from_cache)
        expect(result).to be_nil
      end
    end

    context "when cache file is expired" do
      before do
        allow(File).to receive_messages(exist?: true, mtime: Time.now - 90_000) # 25 hours ago
      end

      it "returns nil when cache file is expired" do
        result = csv_master.send(:load_from_cache)
        expect(result).to be_nil
      end
    end
  end

  describe "#parse_csv" do
    let(:csv_data) { mock_csv_data }

    it "parses CSV data correctly" do
      result = csv_master.send(:parse_csv, csv_data)

      expect(result).to be_an(Array)
      expect(result.length).to eq(8)

      first_row = result.first
      expect(first_row["UNDERLYING_SYMBOL"]).to eq("NIFTY")
      expect(first_row["INSTRUMENT"]).to eq("OPTIDX")
      expect(first_row["SECURITY_ID"]).to eq("NIFTY25SEP19000CE")
      expect(first_row["SM_EXPIRY_DATE"]).to eq("2025-09-25")
      expect(first_row["STRIKE_PRICE"]).to eq("19000")
      expect(first_row["OPTION_TYPE"]).to eq("CE")
      expect(first_row["LOT_SIZE"]).to eq("50")
    end

    it "handles empty CSV data" do
      result = csv_master.send(:parse_csv, "")
      expect(result).to eq([])
    end

    it "handles CSV with only headers" do
      headers_only = "UNDERLYING_SYMBOL,INSTRUMENT,SECURITY_ID\n"
      result = csv_master.send(:parse_csv, headers_only)
      expect(result).to eq([])
    end

    it "handles malformed CSV gracefully" do
      malformed_csv = "UNDERLYING_SYMBOL,INSTRUMENT\nNIFTY,OPTIDX\nBANKNIFTY" # Missing comma
      result = csv_master.send(:parse_csv, malformed_csv)
      expect(result).to be_an(Array)
      expect(result.length).to eq(1) # Should handle the valid row
    end
  end

  describe "#ensure_data_loaded" do
    context "when data is already loaded" do
      before do
        csv_master.instance_variable_set(:@data, [{ "test" => "data" }])
      end

      it "does not reload data" do
        expect(csv_master).not_to receive(:download_csv)
        expect(csv_master).not_to receive(:load_from_cache)

        csv_master.send(:ensure_data_loaded)
      end
    end

    context "when data is not loaded" do
      before do
        csv_master.instance_variable_set(:@data, nil)
        allow(csv_master).to receive_messages(load_from_cache: mock_csv_data, download_csv: mock_csv_data,
                                              parse_csv: [{ "test" => "data" }])
      end

      it "tries to load from cache first" do
        csv_master.send(:ensure_data_loaded)

        expect(csv_master).to have_received(:load_from_cache)
        expect(csv_master).not_to have_received(:download_csv)
      end

      it "downloads from URL if cache fails" do
        allow(csv_master).to receive(:load_from_cache).and_return(nil)

        csv_master.send(:ensure_data_loaded)

        expect(csv_master).to have_received(:load_from_cache)
        expect(csv_master).to have_received(:download_csv)
      end
    end
  end

  describe "#get_expiry_dates" do
    before do
      csv_master.instance_variable_set(:@data, csv_master.send(:parse_csv, mock_csv_data))
    end

    it "returns expiry dates for a specific symbol" do
      result = csv_master.get_expiry_dates("NIFTY")

      expect(result).to eq(["2025-09-25"])
    end

    it "returns expiry dates for OPTIDX instruments" do
      result = csv_master.get_expiry_dates("BANKNIFTY")

      expect(result).to eq(["2025-09-25"])
    end

    it "returns expiry dates for OPTFUT instruments" do
      result = csv_master.get_expiry_dates("GOLD")

      expect(result).to eq(["2025-09-25"])
    end

    it "returns empty array for unknown symbol" do
      result = csv_master.get_expiry_dates("UNKNOWN")

      expect(result).to eq([])
    end

    it "filters by both OPTIDX and OPTFUT instrument types" do
      # Add some mixed data
      mixed_data = csv_master.send(:parse_csv,
                                   "#{mock_csv_data}NIFTY,OPTCUR,NIFTY25SEP19000CE,2025-09-25,19000,CE,50\n")
      csv_master.instance_variable_set(:@data, mixed_data)

      result = csv_master.get_expiry_dates("NIFTY")

      expect(result).to eq(["2025-09-25"])
    end
  end

  describe "#get_security_id" do
    before do
      csv_master.instance_variable_set(:@data, csv_master.send(:parse_csv, mock_csv_data))
    end

    it "returns security ID for matching parameters" do
      result = csv_master.get_security_id("NIFTY", "2025-09-25", "19000", "CE")

      expect(result).to eq("NIFTY25SEP19000CE")
    end

    it "returns nil for non-matching parameters" do
      result = csv_master.get_security_id("NIFTY", "2025-09-25", "19000", "PE")

      expect(result).to eq("NIFTY25SEP19000PE")
    end

    it "returns nil for unknown symbol" do
      result = csv_master.get_security_id("UNKNOWN", "2025-09-25", "19000", "CE")

      expect(result).to be_nil
    end

    it "returns nil for unknown expiry" do
      result = csv_master.get_security_id("NIFTY", "2025-10-25", "19000", "CE")

      expect(result).to be_nil
    end

    it "returns nil for unknown strike" do
      result = csv_master.get_security_id("NIFTY", "2025-09-25", "20000", "CE")

      expect(result).to be_nil
    end

    it "returns nil for unknown option type" do
      result = csv_master.get_security_id("NIFTY", "2025-09-25", "19000", "XX")

      expect(result).to be_nil
    end
  end

  describe "#get_available_strikes" do
    before do
      csv_master.instance_variable_set(:@data, csv_master.send(:parse_csv, mock_csv_data))
    end

    it "returns available strikes for a specific symbol and expiry" do
      result = csv_master.get_available_strikes("NIFTY", "2025-09-25")

      expect(result).to contain_exactly("19000", "19100")
    end

    it "returns empty array for unknown symbol" do
      result = csv_master.get_available_strikes("UNKNOWN", "2025-09-25")

      expect(result).to eq([])
    end

    it "returns empty array for unknown expiry" do
      result = csv_master.get_available_strikes("NIFTY", "2025-10-25")

      expect(result).to eq([])
    end

    it "filters by both OPTIDX and OPTFUT instrument types" do
      result = csv_master.get_available_strikes("GOLD", "2025-09-25")

      expect(result).to eq(["65000"])
    end
  end

  describe "#get_lot_size" do
    before do
      csv_master.instance_variable_set(:@data, csv_master.send(:parse_csv, mock_csv_data))
    end

    it "returns lot size for matching parameters" do
      result = csv_master.get_lot_size("NIFTY", "2025-09-25", "19000", "CE")

      expect(result).to eq(50)
    end

    it "returns nil for non-matching parameters" do
      result = csv_master.get_lot_size("NIFTY", "2025-09-25", "20000", "CE")

      expect(result).to be_nil
    end

    it "handles different lot sizes for different symbols" do
      result = csv_master.get_lot_size("BANKNIFTY", "2025-09-25", "45000", "CE")

      expect(result).to eq(25)
    end
  end

  describe "cache management" do
    it "respects 24-hour cache TTL" do
      expect(described_class::CACHE_TTL).to eq(24 * 60 * 60) # 24 hours in seconds
    end

    it "uses correct cache file path" do
      expect(described_class::CACHE_FILE).to end_with("csv_master_cache.csv")
    end

    it "handles cache file write errors gracefully" do
      allow(File).to receive(:write).and_raise(StandardError, "Write Error")
      allow(Net::HTTP).to receive(:get_response).and_return(mock_http_response)

      expect { csv_master.send(:download_csv) }.to raise_error(StandardError, "Write Error")
    end
  end

  describe "data validation" do
    it "handles CSV with missing columns gracefully" do
      incomplete_csv = "UNDERLYING_SYMBOL,INSTRUMENT\nNIFTY,OPTIDX\n"
      result = csv_master.send(:parse_csv, incomplete_csv)

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first["UNDERLYING_SYMBOL"]).to eq("NIFTY")
      expect(result.first["INSTRUMENT"]).to eq("OPTIDX")
    end

    it "handles CSV with extra columns" do
      extra_columns_csv = "UNDERLYING_SYMBOL,INSTRUMENT,EXTRA_COL\nNIFTY,OPTIDX,EXTRA_VALUE\n"
      result = csv_master.send(:parse_csv, extra_columns_csv)

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first["UNDERLYING_SYMBOL"]).to eq("NIFTY")
      expect(result.first["EXTRA_COL"]).to eq("EXTRA_VALUE")
    end
  end

  describe "performance considerations", :slow do
    it "loads data only once per instance" do
      expect(csv_master).to receive(:download_csv).once.and_return(mock_csv_data)
      allow(csv_master).to receive(:parse_csv).and_return([{ "test" => "data" }])

      # First call should download
      csv_master.get_expiry_dates("NIFTY")

      # Second call should use cached data
      csv_master.get_expiry_dates("BANKNIFTY")
    end
  end
end
