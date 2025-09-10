# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::TickCache do
  before do
    described_class.clear
  end
  describe ".put" do
    it "stores tick data in the cache" do
      tick_data = {
        segment: "IDX_I",
        security_id: "13",
        ltp: 19_500.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      # Verify data is stored
      expect(described_class.ltp("IDX_I", "13")).to eq(19_500.0)
    end

    it "overwrites existing data for same key" do
      tick_data1 = {
        segment: "IDX_I",
        security_id: "13",
        ltp: 19_500.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      tick_data2 = {
        segment: "IDX_I",
        security_id: "13",
        ltp: 19_600.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data1)
      described_class.put(tick_data2)

      expect(described_class.ltp("IDX_I", "13")).to eq(19_600.0)
    end

    it "handles different segments and security IDs" do
      tick_data1 = {
        segment: "IDX_I",
        security_id: "13",
        ltp: 19_500.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      tick_data2 = {
        segment: "NSE_FNO",
        security_id: "12345",
        ltp: 150.0,
        ts: Time.now.to_i,
        symbol: "OPTION"
      }

      described_class.put(tick_data1)
      described_class.put(tick_data2)

      expect(described_class.ltp("IDX_I", "13")).to eq(19_500.0)
      expect(described_class.ltp("NSE_FNO", "12345")).to eq(150.0)
    end

    it "handles nil values" do
      tick_data = {
        segment: "IDX_I",
        security_id: "13",
        ltp: nil,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      expect(described_class.ltp("IDX_I", "13")).to be_nil
    end

    it "handles zero values" do
      tick_data = {
        segment: "IDX_I",
        security_id: "13",
        ltp: 0.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      expect(described_class.ltp("IDX_I", "13")).to eq(0.0)
    end

    it "handles negative values" do
      tick_data = {
        segment: "IDX_I",
        security_id: "13",
        ltp: -100.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      expect(described_class.ltp("IDX_I", "13")).to eq(-100.0)
    end

    it "handles string values" do
      tick_data = {
        segment: "IDX_I",
        security_id: "13",
        ltp: "19500.50",
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      expect(described_class.ltp("IDX_I", "13")).to eq("19500.50")
    end
  end

  describe ".ltp" do
    it "returns nil for non-existent key" do
      expect(described_class.ltp("NONEXISTENT", "999")).to be_nil
    end

    it "returns nil for empty cache" do
      expect(described_class.ltp("IDX_I", "13")).to be_nil
    end

    it "returns correct LTP for existing key" do
      tick_data = {
        segment: "IDX_I",
        security_id: "13",
        ltp: 19_500.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      expect(described_class.ltp("IDX_I", "13")).to eq(19_500.0)
    end

    it "handles different data types" do
      tick_data = {
        segment: "IDX_I",
        security_id: "13",
        ltp: 19_500,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      expect(described_class.ltp("IDX_I", "13")).to eq(19_500)
    end

    it "handles case sensitivity" do
      tick_data = {
        segment: "idx_i",
        security_id: "13",
        ltp: 19_500.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      # Should not find with different case
      expect(described_class.ltp("IDX_I", "13")).to be_nil
      expect(described_class.ltp("idx_i", "13")).to eq(19_500.0)
    end
  end

  describe "concurrent access" do
    it "handles concurrent puts" do
      threads = []

      10.times do |i|
        threads << Thread.new do
          tick_data = {
            segment: "IDX_I",
            security_id: "13",
            ltp: 19_500.0 + i,
            ts: Time.now.to_i,
            symbol: "NIFTY"
          }
          described_class.put(tick_data)
        end
      end

      threads.each(&:join)

      # Should have the last value
      expect(described_class.ltp("IDX_I", "13")).to be >= 19_500.0
    end

    it "handles concurrent reads and writes" do
      tick_data = {
        segment: "IDX_I",
        security_id: "13",
        ltp: 19_500.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      threads = []

      # Reader threads
      5.times do
        threads << Thread.new do
          100.times do
            expect(described_class.ltp("IDX_I", "13")).to eq(19_500.0)
          end
        end
      end

      # Writer threads
      5.times do |i|
        threads << Thread.new do
          100.times do |j|
            new_tick_data = {
              segment: "IDX_I",
              security_id: "13",
              ltp: 19_500.0 + i + j,
              ts: Time.now.to_i,
              symbol: "NIFTY"
            }
            described_class.put(new_tick_data)
          end
        end
      end

      threads.each(&:join)

      # Should still be able to read
      expect(described_class.ltp("IDX_I", "13")).to be >= 19_500.0
    end
  end

  describe "edge cases" do
    it "handles empty segment" do
      tick_data = {
        segment: "",
        security_id: "13",
        ltp: 19_500.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      expect(described_class.ltp("", "13")).to eq(19_500.0)
    end

    it "handles empty security_id" do
      tick_data = {
        segment: "IDX_I",
        security_id: "",
        ltp: 19_500.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      expect(described_class.ltp("IDX_I", "")).to eq(19_500.0)
    end

    it "handles very large numbers" do
      tick_data = {
        segment: "IDX_I",
        security_id: "13",
        ltp: 999_999_999.99,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      expect(described_class.ltp("IDX_I", "13")).to eq(999_999_999.99)
    end

    it "handles very small numbers" do
      tick_data = {
        segment: "IDX_I",
        security_id: "13",
        ltp: 0.0001,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      expect(described_class.ltp("IDX_I", "13")).to eq(0.0001)
    end

    it "handles special characters in segment and security_id" do
      tick_data = {
        segment: "IDX_I_SPECIAL",
        security_id: "13_SPECIAL",
        ltp: 19_500.0,
        ts: Time.now.to_i,
        symbol: "NIFTY"
      }

      described_class.put(tick_data)

      expect(described_class.ltp("IDX_I_SPECIAL", "13_SPECIAL")).to eq(19_500.0)
    end
  end
end
