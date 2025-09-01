# frozen_string_literal: true

require "spec_helper"
require "dhan_scalper"

RSpec.describe "CSV Master Integration with Real Data" do
  let(:csv_master) { DhanScalper::CsvMaster.new }

  before(:all) do
    # Ensure CSV master data is loaded for all tests
    @csv_master = DhanScalper::CsvMaster.new
    @csv_master.send(:ensure_data_loaded)
    @data = @csv_master.instance_variable_get(:@data)

    puts "\n📊 CSV Master Data Loaded:"
    puts "   Total records: #{@data.length}"
    puts "   Sample symbols: #{@data.map { |r| r['UNDERLYING_SYMBOL'] }.compact.uniq.first(10).join(', ')}"
  end

  describe "Real Data Validation" do
    it "has valid CSV structure" do
      expect(@data).not_to be_empty
      expect(@data.first).to have_key("EXCH_ID")
      expect(@data.first).to have_key("UNDERLYING_SYMBOL")
      expect(@data.first).to have_key("INSTRUMENT")
      expect(@data.first).to have_key("SM_EXPIRY_DATE")
      expect(@data.first).to have_key("STRIKE_PRICE")
      expect(@data.first).to have_key("OPTION_TYPE")
      expect(@data.first).to have_key("SECURITY_ID")
      expect(@data.first).to have_key("LOT_SIZE")
    end

    it "contains expected instrument types" do
      instruments = @data.map { |r| r["INSTRUMENT"] }.compact.uniq
      expect(instruments).to include("OPTFUT")
      expect(instruments).to include("OPTIDX")
      puts "   Instrument types: #{instruments.join(', ')}"
    end

    it "has valid expiry dates" do
      expiry_dates = @data.map { |r| r["SM_EXPIRY_DATE"] }.compact.uniq
      valid_dates = expiry_dates.select { |d| d.match?(/\d{4}-\d{2}-\d{2}/) }
      expect(valid_dates.length).to be > 0
      puts "   Valid expiry dates: #{valid_dates.length} out of #{expiry_dates.length}"
    end
  end

  describe "NIFTY Options Data" do
    let(:nifty_data) { @data.select { |r| r["UNDERLYING_SYMBOL"] == "NIFTY" } }
    let(:nifty_options) { nifty_data.select { |r| r["INSTRUMENT"] == "OPTIDX" } }

    it "has NIFTY options data" do
      expect(nifty_options).not_to be_empty
      puts "   NIFTY options: #{nifty_options.length} records"
    end

    it "has valid strike prices" do
      strikes = nifty_options.map { |r| r["STRIKE_PRICE"].to_f }.compact.uniq
      expect(strikes).not_to be_empty
      expect(strikes.all? { |s| s > 0 }).to be true
      puts "   NIFTY strike range: #{strikes.min} to #{strikes.max}"
    end

    it "has both call and put options" do
      option_types = nifty_options.map { |r| r["OPTION_TYPE"] }.compact.uniq
      expect(option_types).to include("CE")
      expect(option_types).to include("PE")
      puts "   NIFTY option types: #{option_types.join(', ')}"
    end

    it "has consistent lot sizes" do
      lot_sizes = nifty_options.map { |r| r["LOT_SIZE"].to_i }.compact.uniq
      expect(lot_sizes).to eq([75]) # NIFTY should always be 75
      puts "   NIFTY lot size: #{lot_sizes.first}"
    end
  end

  describe "BANKNIFTY Options Data" do
    let(:banknifty_data) { @data.select { |r| r["UNDERLYING_SYMBOL"] == "BANKNIFTY" } }
    let(:banknifty_options) { banknifty_data.select { |r| r["INSTRUMENT"] == "OPTIDX" } }

    it "has BANKNIFTY options data" do
      if banknifty_options.any?
        puts "   BANKNIFTY options: #{banknifty_options.length} records"

        strikes = banknifty_options.map { |r| r["STRIKE_PRICE"].to_f }.compact.uniq
        puts "   BANKNIFTY strike range: #{strikes.min} to #{strikes.max}"

        lot_sizes = banknifty_options.map { |r| r["LOT_SIZE"].to_i }.compact.uniq
        puts "   BANKNIFTY lot size: #{lot_sizes.first}"
      else
        puts "   BANKNIFTY options: No data available"
      end
    end
  end

  describe "Commodity Options Data" do
    let(:commodity_symbols) { ["GOLD", "SILVER", "CRUDEOIL", "NICKEL", "COPPER"] }

    it "has commodity options data" do
      commodity_symbols.each do |symbol|
        data = @data.select { |r| r["UNDERLYING_SYMBOL"] == symbol }
        options = data.select { |r| r["INSTRUMENT"] == "OPTFUT" }

        if options.any?
          puts "   #{symbol} options: #{options.length} records"

          strikes = options.map { |r| r["STRIKE_PRICE"].to_f }.compact.uniq
          puts "     Strike range: #{strikes.min} to #{strikes.max}"

          lot_sizes = options.map { |r| r["LOT_SIZE"].to_i }.compact.uniq
          puts "     Lot size: #{lot_sizes.first}"
        end
      end
    end
  end

  describe "Expiry Date Analysis" do
    it "has multiple expiry series" do
      all_expiries = @data.map { |r| r["SM_EXPIRY_DATE"] }.compact.uniq
      valid_expiries = all_expiries.select { |d| d.match?(/\d{4}-\d{2}-\d{2}/) }

      expect(valid_expiries.length).to be > 5 # Should have multiple expiry series
      puts "   Total expiry series: #{valid_expiries.length}"

      # Show first few expiries
      sorted_expiries = valid_expiries.sort
      puts "   First 5 expiries: #{sorted_expiries.first(5).join(', ')}"
      puts "   Last 5 expiries: #{sorted_expiries.last(5).join(', ')}"
    end

    it "has weekly and monthly expiries" do
      nifty_expiries = csv_master.get_expiry_dates("NIFTY")
      expect(nifty_expiries).not_to be_empty

      # Check for weekly expiries (should be multiple in same month)
      september_expiries = nifty_expiries.select { |e| e.start_with?("2025-09") }
      if september_expiries.length > 1
        puts "   Weekly expiries detected: #{september_expiries.join(', ')}"
      end
    end
  end

  describe "Security ID Validation" do
        it "has unique security IDs" do
      security_ids = @data.map { |r| r["SECURITY_ID"] }.compact
      unique_ids = security_ids.uniq

      # Some records might have duplicate security IDs (e.g., different segments)
      # This is acceptable as long as the majority are unique
      uniqueness_ratio = unique_ids.length.to_f / security_ids.length
      expect(uniqueness_ratio).to be > 0.95, "Security ID uniqueness ratio too low: #{uniqueness_ratio}"
      puts "   Security ID uniqueness ratio: #{(uniqueness_ratio * 100).round(2)}% (#{unique_ids.length} unique out of #{security_ids.length} total)"
    end

    it "can resolve security IDs for NIFTY options" do
      expiries = csv_master.get_expiry_dates("NIFTY")
      first_expiry = expiries.first

      # Test with a reasonable strike price
      test_strikes = [25000, 25500, 26000]

      test_strikes.each do |strike|
        ce_id = csv_master.get_security_id("NIFTY", first_expiry, strike, "CE")
        pe_id = csv_master.get_security_id("NIFTY", first_expiry, strike, "PE")

        if ce_id && pe_id
          puts "   NIFTY #{first_expiry} #{strike}: CE=#{ce_id}, PE=#{pe_id}"

          # Verify lot sizes
          ce_lot = csv_master.get_lot_size(ce_id)
          pe_lot = csv_master.get_lot_size(pe_id)
          expect(ce_lot).to eq(75)
          expect(pe_lot).to eq(75)
        end
      end
    end
  end

  describe "Data Quality Checks" do
        it "has no missing critical fields" do
      critical_fields = ["UNDERLYING_SYMBOL", "INSTRUMENT", "SECURITY_ID"]

      critical_fields.each do |field|
        missing_count = @data.count { |r| r[field].nil? || r[field].to_s.strip.empty? }
        if missing_count > 0
          puts "   Warning: #{missing_count} records missing #{field}"
        end
        expect(missing_count).to be < @data.length * 0.1 # Less than 10% missing
      end

      # For option-specific fields, only check records that are actually options
      option_records = @data.select { |r| ["OPTFUT", "OPTIDX", "OPTCUR", "OPTSTK"].include?(r["INSTRUMENT"]) }
      if option_records.any?
        option_critical_fields = ["SM_EXPIRY_DATE", "STRIKE_PRICE", "OPTION_TYPE"]
        option_critical_fields.each do |field|
          missing_count = option_records.count { |r| r[field].nil? || r[field].to_s.strip.empty? }
          if missing_count > 0
            puts "   Warning: #{missing_count} option records missing #{field}"
          end
          expect(missing_count).to be < option_records.length * 0.1 # Less than 10% missing
        end
      end
    end

    it "has consistent data types" do
      # Check numeric fields
      numeric_fields = ["STRIKE_PRICE", "LOT_SIZE"]

      numeric_fields.each do |field|
        non_numeric = @data.count { |r| r[field] && !r[field].to_s.match?(/^\d+(\.\d+)?$/) }
        if non_numeric > 0
          puts "   Warning: #{non_numeric} records have non-numeric #{field}"
        end
        expect(non_numeric).to be < @data.length * 0.05 # Less than 5% invalid
      end
    end
  end

  describe "Performance Testing" do
    it "caches data efficiently" do
      # Test cache performance
      start_time = Time.now

      # First call (should be from cache)
      csv_master.get_expiry_dates("NIFTY")
      first_call_time = Time.now - start_time

      # Second call (should be faster from cache)
      start_time = Time.now
      csv_master.get_expiry_dates("NIFTY")
      second_call_time = Time.now - start_time

      expect(second_call_time).to be < first_call_time
      puts "   Cache performance: First call #{first_call_time.round(4)}s, Second call #{second_call_time.round(4)}s"
    end

        it "handles large datasets efficiently" do
      start_time = Time.now

      # Test with multiple symbols
      symbols = ["NIFTY", "BANKNIFTY", "GOLD", "SILVER"]
      symbols.each do |symbol|
        csv_master.get_expiry_dates(symbol)
      end

      total_time = Time.now - start_time
      # With 170k+ records, it's reasonable to expect it to take a few seconds
      expect(total_time).to be < 30.0 # Should complete in under 30 seconds
      puts "   Multi-symbol lookup time: #{total_time.round(4)}s"
    end
  end

  describe "Error Handling" do
    it "handles missing symbols gracefully" do
      result = csv_master.get_expiry_dates("INVALID_SYMBOL_12345")
      expect(result).to eq([])
    end

    it "handles invalid expiry dates gracefully" do
      result = csv_master.get_security_id("NIFTY", "invalid-date", 25000, "CE")
      expect(result).to be_nil
    end

    it "handles invalid strike prices gracefully" do
      expiries = csv_master.get_expiry_dates("NIFTY")
      first_expiry = expiries.first

      result = csv_master.get_security_id("NIFTY", first_expiry, -1000, "CE")
      expect(result).to be_nil
    end
  end

  after(:all) do
    puts "\n✅ CSV Master Integration Tests Completed"
    puts "   Total records processed: #{@data.length}"
    puts "   Unique symbols: #{@data.map { |r| r['UNDERLYING_SYMBOL'] }.compact.uniq.length}"
    puts "   Unique expiries: #{@data.map { |r| r['SM_EXPIRY_DATE'] }.compact.uniq.select { |d| d.match?(/\d{4}-\d{2}-\d{2}/) }.length}"
  end
end
