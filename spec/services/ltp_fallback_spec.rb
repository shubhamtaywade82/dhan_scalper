# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::Services::LtpFallback do
  let(:logger) { double("Logger") }
  let(:cache) { {} }
  let(:ltp_fallback) { described_class.new(logger: logger, cache: cache, cache_ttl: 30) }

  before do
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  describe "#initialize" do
    it "initializes with correct attributes" do
      expect(ltp_fallback.logger).to eq(logger)
      expect(ltp_fallback.cache).to eq(cache)
      expect(ltp_fallback.cache_ttl).to eq(30)
    end

    it "uses default values when not provided" do
      fallback = described_class.new
      expect(fallback.logger).to be_a(Logger)
      expect(fallback.cache).to be_a(Hash)
      expect(fallback.cache_ttl).to eq(30)
    end
  end

  describe "#get_ltp" do
    let(:segment) { "NSE_FNO" }
    let(:security_id) { "TEST123" }

    context "when data is cached" do
      before do
        cache["#{segment}:#{security_id}"] = {
          ltp: 150.0,
          timestamp: Time.now.to_i,
          cached_at: Time.now
        }
      end

      it "returns cached data" do
        result = ltp_fallback.get_ltp(segment, security_id)
        expect(result).to eq(150.0)
      end

      it "does not make API call" do
        expect(ltp_fallback).not_to receive(:fetch_ltp_from_api)
        ltp_fallback.get_ltp(segment, security_id)
      end
    end

    context "when data is not cached" do
      before do
        allow(ltp_fallback).to receive(:fetch_ltp_from_api).and_return(150.0)
      end

      it "fetches from API and caches result" do
        expect(ltp_fallback).to receive(:fetch_ltp_from_api).with(segment, security_id).and_return(150.0)
        result = ltp_fallback.get_ltp(segment, security_id)
        expect(result).to eq(150.0)
        expect(cache["#{segment}:#{security_id}"]).to include(ltp: 150.0)
      end
    end

    context "when API call fails" do
      before do
        allow(ltp_fallback).to receive(:fetch_ltp_from_api).and_raise(StandardError, "API Error")
      end

      it "returns nil and logs error" do
        expect(logger).to receive(:error).with(/Failed to fetch LTP.*API Error/)
        result = ltp_fallback.get_ltp(segment, security_id)
        expect(result).to be_nil
      end
    end
  end

  describe "#get_multiple_ltp" do
    let(:instruments) do
      [
        { segment: "NSE_FNO", security_id: "TEST1" },
        { segment: "NSE_FNO", security_id: "TEST2" },
        { segment: "IDX_I", security_id: "TEST3" }
      ]
    end

    context "when all data is cached" do
      before do
        cache["NSE_FNO:TEST1"] = { ltp: 100.0, timestamp: Time.now.to_i, cached_at: Time.now }
        cache["NSE_FNO:TEST2"] = { ltp: 200.0, timestamp: Time.now.to_i, cached_at: Time.now }
        cache["IDX_I:TEST3"] = { ltp: 300.0, timestamp: Time.now.to_i, cached_at: Time.now }
      end

      it "returns all cached data" do
        result = ltp_fallback.get_multiple_ltp(instruments)
        expect(result).to eq({
                               "NSE_FNO:TEST1" => 100.0,
                               "NSE_FNO:TEST2" => 200.0,
                               "IDX_I:TEST3" => 300.0
                             })
      end
    end

    context "when some data is missing" do
      before do
        cache["NSE_FNO:TEST1"] = { ltp: 100.0, timestamp: Time.now.to_i, cached_at: Time.now }
        allow(ltp_fallback).to receive(:fetch_segment_ltp).and_return({
                                                                        "NSE_FNO:TEST2" => 200.0,
                                                                        "IDX_I:TEST3" => 300.0
                                                                      })
      end

      it "fetches missing data and returns all" do
        expect(ltp_fallback).to receive(:fetch_segment_ltp).with("NSE_FNO", ["TEST2"])
        expect(ltp_fallback).to receive(:fetch_segment_ltp).with("IDX_I", ["TEST3"])

        result = ltp_fallback.get_multiple_ltp(instruments)
        expect(result).to eq({
                               "NSE_FNO:TEST1" => 100.0,
                               "NSE_FNO:TEST2" => 200.0,
                               "IDX_I:TEST3" => 300.0
                             })
      end
    end

    context "when API calls fail" do
      before do
        allow(ltp_fallback).to receive(:fetch_segment_ltp).and_raise(StandardError, "API Error")
      end

      it "returns empty hash and logs error" do
        expect(logger).to receive(:error).with(/Failed to fetch multiple LTP.*API Error/)
        result = ltp_fallback.get_multiple_ltp(instruments)
        expect(result).to eq({})
      end
    end
  end

  describe "#available?" do
    let(:segment) { "NSE_FNO" }
    let(:security_id) { "TEST123" }

    it "returns true when data is cached and fresh" do
      cache["#{segment}:#{security_id}"] = {
        ltp: 150.0,
        timestamp: Time.now.to_i,
        cached_at: Time.now
      }
      expect(ltp_fallback.available?(segment, security_id)).to be true
    end

    it "returns false when data is not cached" do
      expect(ltp_fallback.available?(segment, security_id)).to be false
    end

    it "returns false when data is stale" do
      cache["#{segment}:#{security_id}"] = {
        ltp: 150.0,
        timestamp: Time.now.to_i,
        cached_at: Time.now - 3600 # 1 hour ago
      }
      expect(ltp_fallback.available?(segment, security_id)).to be false
    end
  end

  describe "#clear_cache" do
    before do
      cache["NSE_FNO:TEST1"] = { ltp: 100.0 }
      cache["IDX_I:TEST2"] = { ltp: 200.0 }
    end

    it "clears all cached data" do
      expect(cache).not_to be_empty
      ltp_fallback.clear_cache
      expect(cache).to be_empty
    end
  end

  describe "#cache_stats" do
    before do
      cache["NSE_FNO:TEST1"] = { ltp: 100.0, cached_at: Time.now }
      cache["IDX_I:TEST2"] = { ltp: 200.0, cached_at: Time.now - 60 }
    end

    it "returns cache statistics" do
      stats = ltp_fallback.cache_stats
      expect(stats).to include(
        total_entries: 2,
        fresh_entries: 1,
        stale_entries: 1
      )
    end
  end

  describe "#fetch_ltp_from_api" do
    let(:segment) { "NSE_FNO" }
    let(:security_id) { "TEST123" }

    before do
      # Mock DhanHQ::Models::MarketFeed
      market_feed_class = double("MarketFeed")
      allow(DhanScalper).to receive(:const_defined?).with("DhanHQ::Models::MarketFeed").and_return(true)
      stub_const("DhanHQ::Models::MarketFeed", market_feed_class)

      mock_response = double("Response")
      allow(mock_response).to receive(:[]).with("last_price").and_return("150.0")
      allow(market_feed_class).to receive(:ltp).and_return(mock_response)
    end

    it "fetches LTP from DhanHQ API" do
      result = ltp_fallback.fetch_ltp_from_api(segment, security_id)
      expect(result).to eq(150.0)
    end

    it "handles API errors gracefully" do
      allow(DhanScalper).to receive(:const_defined?).with("DhanHQ::Models::MarketFeed").and_return(false)
      expect { ltp_fallback.fetch_ltp_from_api(segment, security_id) }.to raise_error(LoadError)
    end

    it "handles invalid response data" do
      market_feed_class = double("MarketFeed")
      allow(DhanScalper).to receive(:const_defined?).with("DhanHQ::Models::MarketFeed").and_return(true)
      stub_const("DhanHQ::Models::MarketFeed", market_feed_class)

      mock_response = double("Response")
      allow(mock_response).to receive(:[]).with("last_price").and_return(nil)
      allow(market_feed_class).to receive(:ltp).and_return(mock_response)

      result = ltp_fallback.fetch_ltp_from_api(segment, security_id)
      expect(result).to be_nil
    end
  end

  describe "#fetch_segment_ltp" do
    let(:segment) { "NSE_FNO" }
    let(:security_ids) { %w[TEST1 TEST2] }

    before do
      # Mock DhanHQ::Models::MarketFeed
      market_feed_class = double("MarketFeed")
      allow(DhanScalper).to receive(:const_defined?).with("DhanHQ::Models::MarketFeed").and_return(true)
      stub_const("DhanHQ::Models::MarketFeed", market_feed_class)

      mock_response = [
        { "security_id" => "TEST1", "last_price" => "100.0" },
        { "security_id" => "TEST2", "last_price" => "200.0" }
      ]
      allow(market_feed_class).to receive(:ltp).and_return(mock_response)
    end

    it "fetches LTP for multiple securities" do
      result = ltp_fallback.fetch_segment_ltp(segment, security_ids)
      expect(result).to eq({
                             "NSE_FNO:TEST1" => 100.0,
                             "NSE_FNO:TEST2" => 200.0
                           })
    end

    it "handles API errors gracefully" do
      allow(DhanScalper).to receive(:const_defined?).with("DhanHQ::Models::MarketFeed").and_return(false)
      expect { ltp_fallback.fetch_segment_ltp(segment, security_ids) }.to raise_error(LoadError)
    end

    it "handles empty response" do
      market_feed_class = double("MarketFeed")
      allow(DhanScalper).to receive(:const_defined?).with("DhanHQ::Models::MarketFeed").and_return(true)
      stub_const("DhanHQ::Models::MarketFeed", market_feed_class)

      allow(market_feed_class).to receive(:ltp).and_return([])

      result = ltp_fallback.fetch_segment_ltp(segment, security_ids)
      expect(result).to eq({})
    end
  end

  describe "caching behavior" do
    let(:segment) { "NSE_FNO" }
    let(:security_id) { "TEST123" }

    it "respects cache TTL" do
      # Set short TTL
      short_ttl_fallback = described_class.new(cache: cache, cache_ttl: 1)

      # Cache data
      cache["#{segment}:#{security_id}"] = {
        ltp: 150.0,
        timestamp: Time.now.to_i,
        cached_at: Time.now - 2 # 2 seconds ago
      }

      # Should be stale
      expect(short_ttl_fallback.available?(segment, security_id)).to be false
    end

    it "updates cache on successful API calls" do
      allow(ltp_fallback).to receive(:fetch_ltp_from_api).and_return(150.0)

      ltp_fallback.get_ltp(segment, security_id)

      expect(cache["#{segment}:#{security_id}"]).to include(
        ltp: 150.0,
        timestamp: be_a(Integer),
        cached_at: be_a(Time)
      )
    end
  end

  describe "error handling" do
    it "handles network timeouts" do
      allow(ltp_fallback).to receive(:fetch_ltp_from_api).and_raise(Timeout::Error, "Request timeout")

      expect(logger).to receive(:error).with(/Failed to fetch LTP.*Request timeout/)
      result = ltp_fallback.get_ltp("NSE_FNO", "TEST123")
      expect(result).to be_nil
    end

    it "handles JSON parsing errors" do
      allow(ltp_fallback).to receive(:fetch_ltp_from_api).and_raise(JSON::ParserError, "Invalid JSON")

      expect(logger).to receive(:error).with(/Failed to fetch LTP.*Invalid JSON/)
      result = ltp_fallback.get_ltp("NSE_FNO", "TEST123")
      expect(result).to be_nil
    end

    it "handles invalid security IDs" do
      allow(ltp_fallback).to receive(:fetch_ltp_from_api).and_raise(ArgumentError, "Invalid security ID")

      expect(logger).to receive(:error).with(/Failed to fetch LTP.*Invalid security ID/)
      result = ltp_fallback.get_ltp("NSE_FNO", "INVALID")
      expect(result).to be_nil
    end
  end
end
