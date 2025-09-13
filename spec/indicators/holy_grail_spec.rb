# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Indicators::HolyGrail do
  let(:candle_data) do
    {
      "timestamp" => (1..200).map { |i| Time.now - ((200 - i) * 60) },
      "open" => (1..200).map { |_i| rand(24_900..25_100) },
      "high" => (1..200).map { |_i| rand(25_050..25_150) },
      "low" => (1..200).map { |_i| rand(24_850..24_950) },
      "close" => (1..200).map { |_i| rand(24_950..25_050) },
      "volume" => (1..200).map { |_i| rand(1_000..10_000) },
    }
  end

  let(:holy_grail) { described_class.new(candles: candle_data) }

  describe "#initialize" do
    it "requires at least 100 candles" do
      insufficient_data = {
        "close" => (1..50).map { |_i| rand(24_950..25_050) }
      }

      expect {
        described_class.new(candles: insufficient_data)
      }.to raise_error(ArgumentError, "need ≥ 100 candles")
    end

    it "accepts sufficient data" do
      expect { described_class.new(candles: candle_data) }.not_to raise_error
    end
  end

  describe "#call" do
    context "with bullish market conditions" do
      before do
        # Create bullish candle data
        bullish_closes = (1..200).map { |i| 25_000 + (i * 2) } # Upward trend
        bullish_highs = bullish_closes.map { |c| c + rand(10..30) }
        bullish_lows = bullish_closes.map { |c| c - rand(5..15) }

        candle_data["close"] = bullish_closes
        candle_data["high"] = bullish_highs
        candle_data["low"] = bullish_lows
      end

      it "returns a struct with expected fields" do
        result = holy_grail.call
        expect(result).to respond_to(:bias)
        expect(result).to respond_to(:momentum)
        expect(result).to respond_to(:adx)
        expect(result).to respond_to(:rsi14)
        expect(result).to respond_to(:atr14)
        expect(result).to respond_to(:proceed?)
        expect(result).to respond_to(:signal_strength)
      end

      it "identifies bullish bias correctly" do
        result = holy_grail.call
        expect(result.bias).to eq(:bullish)
      end

      it "shows appropriate momentum" do
        result = holy_grail.call
        expect([:strong, :up, :flat]).to include(result.momentum)
      end

      it "has high ADX indicating strong trend" do
        result = holy_grail.call
        expect(result.adx).to be > 25
      end

      it "shows bullish RSI" do
        result = holy_grail.call
        expect(result.rsi14).to be >= 50
      end

      it "indicates bullish MACD" do
        result = holy_grail.call
        expect(result.macd).to be_a(Hash)
        expect(result.macd[:macd]).to be > result.macd[:signal]
      end
    end

    context "with bearish market conditions" do
      before do
        # Create bearish candle data
        bearish_closes = (1..200).map { |i| 25_000 - (i * 2) } # Downward trend
        bearish_highs = bearish_closes.map { |c| c + rand(5..15) }
        bearish_lows = bearish_closes.map { |c| c - rand(10..30) }

        candle_data["close"] = bearish_closes
        candle_data["high"] = bearish_highs
        candle_data["low"] = bearish_lows
      end

      it "identifies bearish bias correctly" do
        result = holy_grail.call
        expect(result.bias).to eq(:bearish)
      end

      it "shows appropriate momentum" do
        result = holy_grail.call
        expect([:strong, :down, :flat]).to include(result.momentum)
      end

      it "has high ADX indicating strong trend" do
        result = holy_grail.call
        expect(result.adx).to be > 25
      end

      it "shows bearish RSI" do
        result = holy_grail.call
        expect(result.rsi14).to be < 50
      end

      it "indicates bearish MACD" do
        result = holy_grail.call
        expect(result.macd).to be_a(Hash)
        expect(result.macd[:macd]).to be < result.macd[:signal]
      end
    end

    context "with sideways market conditions" do
      before do
        # Create sideways candle data
        sideways_closes = (1..200).map { |i| 25_000 + (Math.sin(i * 0.1) * 50) } # Sideways oscillation
        sideways_highs = sideways_closes.map { |c| c + rand(5..20) }
        sideways_lows = sideways_closes.map { |c| c - rand(5..20) }

        candle_data["close"] = sideways_closes
        candle_data["high"] = sideways_highs
        candle_data["low"] = sideways_lows
      end

      it "identifies appropriate bias" do
        result = holy_grail.call
        expect([:neutral, :bullish, :bearish]).to include(result.bias)
      end

      it "shows appropriate momentum" do
        result = holy_grail.call
        expect([:weak, :flat, :up, :down]).to include(result.momentum)
      end

      it "has variable ADX" do
        result = holy_grail.call
        expect(result.adx).to be >= 0
        expect(result.adx).to be <= 100
      end

      it "shows neutral RSI" do
        result = holy_grail.call
        expect(result.rsi14).to be_between(0, 100)
      end

      it "indicates appropriate MACD" do
        result = holy_grail.call
        expect(result.macd).to be_a(Hash)
        expect(result.macd).to have_key(:macd)
        expect(result.macd).to have_key(:signal)
        expect(result.macd).to have_key(:hist)
      end
    end

    context "with edge cases" do
      it "handles zero values gracefully" do
        zero_data = candle_data.dup
        zero_data["close"] = [0] * 200
        zero_data["high"] = [0] * 200
        zero_data["low"] = [0] * 200

        holy_grail_zero = described_class.new(candles: zero_data)
        expect { holy_grail_zero.call }.not_to raise_error
      end

      it "handles negative values gracefully" do
        negative_data = candle_data.dup
        negative_data["close"] = (1..200).map(&:-@)
        negative_data["high"] = (1..200).map { |i| -i + 10 }
        negative_data["low"] = (1..200).map { |i| -i - 10 }

        holy_grail_negative = described_class.new(candles: negative_data)
        expect { holy_grail_negative.call }.not_to raise_error
      end

      it "handles very large values" do
        large_data = candle_data.dup
        large_data["close"] = (1..200).map { |i| 1_000_000 + i }
        large_data["high"] = (1..200).map { |i| 1_000_000 + i + 100 }
        large_data["low"] = (1..200).map { |i| 1_000_000 + i - 100 }

        holy_grail_large = described_class.new(candles: large_data)
        expect { holy_grail_large.call }.not_to raise_error
      end
    end
  end

  describe "#generate_options_signal" do
    it "generates bullish signal for strong bullish indicators" do
      signal, strength = holy_grail.send(:generate_options_signal, :bullish, :strong, 30.0, 70.0, { macd: 1.0, signal: 0.5, hist: 0.5 })
      expect([:bullish, :buy_ce, :buy_ce_weak]).to include(signal)
      expect(strength).to be > 0.5
    end

    it "generates bearish signal for strong bearish indicators" do
      signal, strength = holy_grail.send(:generate_options_signal, :bearish, :strong, 30.0, 30.0, { macd: -1.0, signal: -0.5, hist: -0.5 })
      expect([:bearish, :buy_pe, :buy_pe_weak]).to include(signal)
      expect(strength).to be > 0.5
    end

    it "generates weak signal for mixed indicators" do
      signal, strength = holy_grail.send(:generate_options_signal, :bullish, :weak, 15.0, 50.0, { macd: 0.1, signal: 0.1, hist: 0.0 })
      expect(signal).to eq(:none)
      expect(strength).to be < 0.5
    end

    it "handles edge cases in signal generation" do
      # Test with extreme values
      signal, strength = holy_grail.send(:generate_options_signal, :bullish, :strong, 50.0, 90.0, { macd: 2.0, signal: 1.0, hist: 1.0 })
      expect([:bullish, :buy_ce, :buy_ce_weak]).to include(signal)
      expect(strength).to be_between(0.0, 1.0)
    end
  end

  describe "performance characteristics" do
    it "processes large datasets efficiently" do
      large_candle_data = {
        "timestamp" => (1..1_000).map { |i| Time.now - ((1_000 - i) * 60) },
        "open" => (1..1_000).map { |_i| rand(24_900..25_100) },
        "high" => (1..1_000).map { |_i| rand(25_050..25_150) },
        "low" => (1..1_000).map { |_i| rand(24_850..24_950) },
        "close" => (1..1_000).map { |_i| rand(24_950..25_050) },
        "volume" => (1..1_000).map { |_i| rand(1_000..10_000) },
      }

      large_holy_grail = described_class.new(candles: large_candle_data)

      start_time = Time.now
      result = large_holy_grail.call
      duration = Time.now - start_time

      expect(duration).to be < 2.0 # Should complete within 2 seconds
      expect(result).not_to be_nil
    end

    it "handles concurrent calculations" do
      threads = []
      results = []

      5.times do |_i|
        threads << Thread.new do
          holy_grail_instance = described_class.new(candles: candle_data)
          results << holy_grail_instance.call
        end
      end

      threads.each(&:join)

      expect(results.length).to eq(5)
      expect(results.all? { |r| r.respond_to?(:bias) }).to be true
    end
  end
end
