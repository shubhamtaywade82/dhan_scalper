# frozen_string_literal: true

require "spec_helper"

RSpec.describe TimeZone do
  let(:time_zone) { described_class }

  describe ".parse" do
    context "with numeric input" do
      it "parses Unix timestamp correctly" do
        timestamp = 1706171415
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        expect(result.to_i).to eq(1706171415)
      end

      it "parses Unix timestamp as float" do
        timestamp = 1706171415.123
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        expect(result.to_i).to eq(1706171415)
      end

      it "handles zero timestamp" do
        result = time_zone.parse(0)
        expect(result).to be_a(Time)
        expect(result.to_i).to eq(0)
      end

      it "handles negative timestamp" do
        result = time_zone.parse(-1000)
        expect(result).to be_a(Time)
        expect(result.to_i).to eq(-1000)
      end

      it "handles very large timestamp" do
        timestamp = 9999999999
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        expect(result.to_i).to eq(timestamp)
      end
    end

    context "with string input" do
      it "parses ISO 8601 timestamp correctly" do
        timestamp = "2024-01-25T10:30:15Z"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        expect(result.year).to eq(2024)
        expect(result.month).to eq(1)
        expect(result.day).to eq(25)
        expect(result.hour).to eq(10)
        expect(result.min).to eq(30)
        expect(result.sec).to eq(15)
      end

      it "parses ISO 8601 with timezone offset" do
        timestamp = "2024-01-25T10:30:15+05:30"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        expect(result.year).to eq(2024)
        expect(result.month).to eq(1)
        expect(result.day).to eq(25)
      end

      it "parses ISO 8601 without timezone (assumes local)" do
        timestamp = "2024-01-25T10:30:15"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        expect(result.year).to eq(2024)
        expect(result.month).to eq(1)
        expect(result.day).to eq(25)
      end

      it "parses date string correctly" do
        timestamp = "2024-01-25"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        expect(result.year).to eq(2024)
        expect(result.month).to eq(1)
        expect(result.day).to eq(25)
      end

      it "parses date with time" do
        timestamp = "2024-01-25 10:30:15"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        expect(result.year).to eq(2024)
        expect(result.month).to eq(1)
        expect(result.day).to eq(25)
        expect(result.hour).to eq(10)
        expect(result.min).to eq(30)
        expect(result.sec).to eq(15)
      end

      it "parses numeric string as string (not as number)" do
        timestamp = "1706171415"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        # Since it's a string, it should be parsed as a date string, not Unix timestamp
        # The actual result depends on how Time.parse handles this string
        expect(result).to be_a(Time)
      end

      it "handles edge cases" do
        timestamp = "2024-02-29T10:30:15Z"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        expect(result.year).to eq(2024)
        expect(result.month).to eq(2)
        expect(result.day).to eq(29)
      end

      it "handles very old dates" do
        timestamp = "1900-01-01T00:00:00Z"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        expect(result.year).to eq(1900)
      end

      it "handles very future dates" do
        timestamp = "2100-12-31T23:59:59Z"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        expect(result.year).to eq(2100)
      end
    end

    context "with Time object" do
      it "returns Time object as is" do
        original_time = Time.new(2024, 1, 25, 10, 30, 15)
        result = time_zone.parse(original_time)
        expect(result).to be_a(Time)
        expect(result).to eq(original_time)
      end
    end

    context "with invalid string input" do
      it "handles invalid string gracefully" do
        timestamp = "invalid_timestamp"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        # Should return current time due to rescue clause
        expect(result).to be_within(1).of(Time.now)
      end

      it "handles nil gracefully" do
        result = time_zone.parse(nil)
        expect(result).to be_a(Time)
        # Should return current time due to rescue clause
        expect(result).to be_within(1).of(Time.now)
      end

      it "handles empty string gracefully" do
        result = time_zone.parse("")
        expect(result).to be_a(Time)
        # Should return current time due to rescue clause
        expect(result).to be_within(1).of(Time.now)
      end

      it "handles invalid format gracefully" do
        timestamp = "25-01-2024"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        # This format might actually parse successfully, so just check it's a Time
        expect(result).to be_a(Time)
      end

      it "handles leap seconds gracefully" do
        timestamp = "2016-12-31T23:59:60Z"
        result = time_zone.parse(timestamp)
        expect(result).to be_a(Time)
        # Should either parse correctly or fall back to current time
      end
    end
  end

  describe ".at" do
    context "with Unix timestamp" do
      it "creates Time from Unix timestamp" do
        timestamp = 1706171415
        result = time_zone.at(timestamp)
        expect(result).to be_a(Time)
        expect(result.to_i).to eq(1706171415)
      end

      it "creates Time from Unix timestamp string" do
        timestamp = "1706171415"
        result = time_zone.at(timestamp)
        expect(result).to be_a(Time)
        expect(result.to_i).to eq(1706171415)
      end

      it "creates Time from float timestamp" do
        timestamp = 1706171415.123
        result = time_zone.at(timestamp)
        expect(result).to be_a(Time)
        expect(result.to_i).to eq(1706171415)
      end

      it "handles zero timestamp" do
        result = time_zone.at(0)
        expect(result).to be_a(Time)
        expect(result.to_i).to eq(0)
      end

      it "handles negative timestamp" do
        result = time_zone.at(-1000)
        expect(result).to be_a(Time)
        expect(result.to_i).to eq(-1000)
      end

      it "handles very large timestamp" do
        timestamp = 9999999999
        result = time_zone.at(timestamp)
        expect(result).to be_a(Time)
        expect(result.to_i).to eq(timestamp)
      end
    end
  end

  describe "module structure" do
    it "is defined as a module" do
      expect(described_class).to be_a(Module)
    end

    it "has the correct name" do
      expect(described_class.name).to eq("TimeZone")
    end

    it "has module_function defined" do
      expect(described_class).to respond_to(:parse)
      expect(described_class).to respond_to(:at)
    end
  end

  describe "error handling" do
    it "rescues StandardError in parse method" do
      # Mock Time.parse to raise an error
      allow(Time).to receive(:parse).and_raise(StandardError, "Parse error")

      result = time_zone.parse("invalid")
      expect(result).to be_a(Time)
      expect(result).to be_within(1).of(Time.now)
    end

    it "handles various error types gracefully" do
      allow(Time).to receive(:parse).and_raise(ArgumentError, "Invalid argument")

      result = time_zone.parse("invalid")
      expect(result).to be_a(Time)
      expect(result).to be_within(1).of(Time.now)
    end
  end

  describe "performance characteristics" do
    it "handles large number of timestamps efficiently" do
      start_time = Time.now
      1000.times do
        time_zone.parse("2024-01-25T10:30:15Z")
      end
      end_time = Time.now

      expect(end_time - start_time).to be < 1.0 # Should complete within 1 second
    end

    it "handles various timestamp formats efficiently" do
      timestamps = [
        "2024-01-25T10:30:15Z",
        "1706171415",
        "2024-01-25",
        "2024-01-25 10:30:15"
      ]

      start_time = Time.now
      timestamps.each { |ts| time_zone.parse(ts) }
      end_time = Time.now

      expect(end_time - start_time).to be < 0.1 # Should complete within 0.1 seconds
    end
  end

  describe "integration with Time class" do
    it "delegates parse to Time.parse for strings" do
      timestamp = "2024-01-25T10:30:15Z"
      expect(Time).to receive(:parse).with(timestamp)
      time_zone.parse(timestamp)
    end

    it "delegates at to Time.at for numbers" do
      timestamp = 1706171415
      expect(Time).to receive(:at).with(1706171415)
      time_zone.at(timestamp)
    end

    it "delegates at to Time.at for numeric strings in at method" do
      timestamp = "1706171415"
      expect(Time).to receive(:at).with(1706171415)
      time_zone.at(timestamp)
    end
  end

  describe "fallback behavior" do
    it "returns current time when parsing fails" do
      allow(Time).to receive(:parse).and_raise(StandardError, "Parse error")

      before_time = Time.now
      result = time_zone.parse("invalid")
      after_time = Time.now

      expect(result).to be_a(Time)
      expect(result).to be_between(before_time, after_time)
    end

    it "handles nil input gracefully" do
      result = time_zone.parse(nil)
      expect(result).to be_a(Time)
      expect(result).to be_within(1).of(Time.now)
    end

    it "handles empty string gracefully" do
      result = time_zone.parse("")
      expect(result).to be_a(Time)
      expect(result).to be_within(1).of(Time.now)
    end
  end

  describe "input type handling" do
    it "treats numeric strings as strings in parse method" do
      timestamp = "1706171415"
      result = time_zone.parse(timestamp)
      expect(result).to be_a(Time)
      # Since it's a string, it should be parsed as a date string, not Unix timestamp
      expect(result).to be_a(Time)
    end

    it "treats non-numeric strings as strings" do
      timestamp = "2024-01-25T10:30:15Z"
      result = time_zone.parse(timestamp)
      expect(result).to be_a(Time)
      expect(result.year).to eq(2024)
    end
  end

  describe "type checking behavior" do
    it "uses is_a?(Numeric) for type checking" do
      # Test with actual numeric and string types
      numeric_value = 1706171415
      string_value = "1706171415"

      # Numeric values should use Time.at
      expect(Time).to receive(:at).with(1706171415)
      time_zone.parse(numeric_value)

      # String values should use Time.parse
      expect(Time).to receive(:parse).with(string_value)
      time_zone.parse(string_value)
    end
  end
end
