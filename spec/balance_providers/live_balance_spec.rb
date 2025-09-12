# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::BalanceProviders::LiveBalance do
  let(:live_balance) { described_class.new }

  before do
    # Mock DhanHQ::Models::Funds to avoid actual API calls
    stub_const("DhanHQ::Models::Funds", double)
  end

  describe "#initialize" do
    it "initializes with empty cache" do
      expect(live_balance.instance_variable_get(:@cache)).to eq({})
      expect(live_balance.instance_variable_get(:@cache_time)).to be_nil
      expect(live_balance.instance_variable_get(:@cache_ttl)).to eq(30)
    end
  end

  describe "#available_balance" do
    it "refreshes cache if needed and returns available balance" do
      allow(live_balance).to receive(:refresh_cache_if_needed)
      allow(live_balance.instance_variable_get(:@cache)).to receive(:[]).with(:available).and_return(100_000.0)

      result = live_balance.available_balance

      expect(live_balance).to have_received(:refresh_cache_if_needed)
      expect(result).to eq(100_000.0)
    end

    it "returns 0.0 when cache is empty" do
      allow(live_balance).to receive(:refresh_cache_if_needed)
      allow(live_balance.instance_variable_get(:@cache)).to receive(:[]).with(:available).and_return(nil)

      result = live_balance.available_balance
      expect(result).to eq(0.0)
    end
  end

  describe "#total_balance" do
    it "refreshes cache if needed and returns total balance" do
      allow(live_balance).to receive(:refresh_cache_if_needed)
      allow(live_balance.instance_variable_get(:@cache)).to receive(:[]).with(:total).and_return(200_000.0)

      result = live_balance.total_balance

      expect(live_balance).to have_received(:refresh_cache_if_needed)
      expect(result).to eq(200_000.0)
    end

    it "returns 0.0 when cache is empty" do
      allow(live_balance).to receive(:refresh_cache_if_needed)
      allow(live_balance.instance_variable_get(:@cache)).to receive(:[]).with(:total).and_return(nil)

      result = live_balance.total_balance
      expect(result).to eq(0.0)
    end
  end

  describe "#used_balance" do
    it "refreshes cache if needed and returns used balance" do
      allow(live_balance).to receive(:refresh_cache_if_needed)
      allow(live_balance.instance_variable_get(:@cache)).to receive(:[]).with(:used).and_return(50_000.0)

      result = live_balance.used_balance

      expect(live_balance).to have_received(:refresh_cache_if_needed)
      expect(result).to eq(50_000.0)
    end

    it "returns 0.0 when cache is empty" do
      allow(live_balance).to receive(:refresh_cache_if_needed)
      allow(live_balance.instance_variable_get(:@cache)).to receive(:[]).with(:used).and_return(nil)

      result = live_balance.used_balance
      expect(result).to eq(0.0)
    end
  end

  describe "#update_balance" do
    it "refreshes cache and returns total balance" do
      allow(live_balance).to receive(:refresh_cache)
      allow(live_balance.instance_variable_get(:@cache)).to receive(:[]).with(:total).and_return(200_000.0)

      result = live_balance.update_balance(50_000, type: :debit)

      expect(live_balance).to have_received(:refresh_cache)
      expect(result).to eq(200_000.0)
    end

    it "returns 0.0 when cache is empty" do
      allow(live_balance).to receive(:refresh_cache)
      allow(live_balance.instance_variable_get(:@cache)).to receive(:[]).with(:total).and_return(nil)

      result = live_balance.update_balance(50_000, type: :debit)
      expect(result).to eq(0.0)
    end
  end

  describe "#refresh_cache_if_needed" do
    context "when cache is valid" do
      before do
        live_balance.instance_variable_set(:@cache_time, Time.now)
        live_balance.instance_variable_set(:@cache, { available: 100_000.0, used: 0.0, total: 100_000.0 })
      end

      it "does not refresh cache if TTL is not expired" do
        allow(live_balance).to receive(:refresh_cache)

        live_balance.send(:refresh_cache_if_needed)

        expect(live_balance).not_to have_received(:refresh_cache)
      end
    end

    context "when cache is expired" do
      before do
        live_balance.instance_variable_set(:@cache_time, Time.now - 60) # 60 seconds ago
        live_balance.instance_variable_set(:@cache, { available: 100_000.0, used: 0.0, total: 100_000.0 })
      end

      it "refreshes cache if TTL is expired" do
        allow(live_balance).to receive(:refresh_cache)

        live_balance.send(:refresh_cache_if_needed)

        expect(live_balance).to have_received(:refresh_cache)
      end
    end

    context "when cache is nil" do
      before do
        live_balance.instance_variable_set(:@cache_time, nil)
        live_balance.instance_variable_set(:@cache, nil)
      end

      it "refreshes cache if cache time is nil" do
        allow(live_balance).to receive(:refresh_cache)

        live_balance.send(:refresh_cache_if_needed)

        expect(live_balance).to have_received(:refresh_cache)
      end
    end
  end

  describe "#refresh_cache" do
    context "when API call succeeds" do
      let(:mock_funds) do
        double(
          available_balance: 100_000.0,
          total_balance: 200_000.0,
        )
      end

      before do
        allow(DhanHQ::Models::Funds).to receive(:fetch).and_return(mock_funds)
      end

      it "updates cache with API data" do
        live_balance.send(:refresh_cache)

        cache = live_balance.instance_variable_get(:@cache)
        expect(cache[:available]).to eq(100_000.0)
        expect(cache[:total]).to eq(200_000.0)
        expect(cache[:used]).to eq(100_000.0) # total - available
        expect(live_balance.instance_variable_get(:@cache_time)).to be_within(1).of(Time.now)
      end

      it "calculates used balance as total - available" do
        live_balance.send(:refresh_cache)

        cache = live_balance.instance_variable_get(:@cache)
        expect(cache[:used]).to eq(cache[:total] - cache[:available])
      end
    end

    context "when API call fails" do
      before do
        allow(DhanHQ::Models::Funds).to receive(:fetch).and_raise(StandardError, "API Error")
      end

      context "when no existing cache" do
        before do
          live_balance.instance_variable_set(:@cache, {})
          live_balance.instance_variable_set(:@cache_time, nil)
        end

        it "sets default cache values" do
          live_balance.send(:refresh_cache)

          cache = live_balance.instance_variable_get(:@cache)
          expect(cache[:available]).to eq(100_000.0)
          expect(cache[:total]).to eq(100_000.0)
          expect(cache[:used]).to eq(0.0)
        end
      end

      context "when existing cache exists" do
        before do
          live_balance.instance_variable_set(:@cache, { available: 50_000.0, used: 50_000.0, total: 100_000.0 })
          live_balance.instance_variable_set(:@cache_time, Time.now - 60)
        end

        it "keeps existing cache values" do
          live_balance.send(:refresh_cache)

          cache = live_balance.instance_variable_get(:@cache)
          expect(cache[:available]).to eq(50_000.0)
          expect(cache[:total]).to eq(100_000.0)
          expect(cache[:used]).to eq(50_000.0)
        end
      end
    end

    context "when API response is unexpected" do
      context "when funds object doesn't respond to available_balance" do
        let(:mock_funds) { double }

        before do
          allow(DhanHQ::Models::Funds).to receive(:fetch).and_return(mock_funds)
        end

        it "falls back to default values" do
          live_balance.send(:refresh_cache)

          cache = live_balance.instance_variable_get(:@cache)
          expect(cache[:available]).to eq(100_000.0)
          expect(cache[:total]).to eq(100_000.0)
          expect(cache[:used]).to eq(0.0)
        end
      end

      context "when funds object is nil" do
        before do
          allow(DhanHQ::Models::Funds).to receive(:fetch).and_return(nil)
        end

        it "falls back to default values" do
          live_balance.send(:refresh_cache)

          cache = live_balance.instance_variable_get(:@cache)
          expect(cache[:available]).to eq(100_000.0)
          expect(cache[:total]).to eq(100_000.0)
          expect(cache[:used]).to eq(0.0)
        end
      end
    end
  end

  describe "cache TTL behavior" do
    it "respects the 30-second TTL setting" do
      expect(live_balance.instance_variable_get(:@cache_ttl)).to eq(30)
    end

    it "refreshes cache after TTL expires" do
      # Set cache time to 31 seconds ago (expired)
      live_balance.instance_variable_set(:@cache_time, Time.now - 31)
      live_balance.instance_variable_set(:@cache, { available: 100_000.0, used: 0.0, total: 100_000.0 })

      allow(live_balance).to receive(:refresh_cache)

      live_balance.send(:refresh_cache_if_needed)

      expect(live_balance).to have_received(:refresh_cache)
    end

    it "does not refresh cache before TTL expires" do
      # Set cache time to 29 seconds ago (not expired)
      live_balance.instance_variable_set(:@cache_time, Time.now - 29)
      live_balance.instance_variable_set(:@cache, { available: 100_000.0, used: 0.0, total: 100_000.0 })

      allow(live_balance).to receive(:refresh_cache)

      live_balance.send(:refresh_cache_if_needed)

      expect(live_balance).not_to have_received(:refresh_cache)
    end
  end

  describe "error handling" do
    it "handles network errors gracefully" do
      allow(DhanHQ::Models::Funds).to receive(:fetch).and_raise(StandardError, "Network Error")

      expect { live_balance.send(:refresh_cache) }.not_to raise_error
    end

    it "handles API errors gracefully" do
      allow(DhanHQ::Models::Funds).to receive(:fetch).and_raise(StandardError, "API Error")

      expect { live_balance.send(:refresh_cache) }.not_to raise_error
    end

    it "handles unexpected response formats" do
      allow(DhanHQ::Models::Funds).to receive(:fetch).and_return("unexpected_string")

      expect { live_balance.send(:refresh_cache) }.not_to raise_error
    end
  end

  describe "balance calculation edge cases" do
    context "when total balance is less than available balance" do
      let(:mock_funds) do
        double(
          available_balance: 200_000.0,
          total_balance: 100_000.0,
        )
      end

      before do
        allow(DhanHQ::Models::Funds).to receive(:fetch).and_return(mock_funds)
      end

      it "handles negative used balance gracefully" do
        live_balance.send(:refresh_cache)

        cache = live_balance.instance_variable_get(:@cache)
        expect(cache[:used]).to eq(-100_000.0) # 100_000 - 200_000
      end
    end

    context "when balances are zero" do
      let(:mock_funds) do
        double(
          available_balance: 0.0,
          total_balance: 0.0,
        )
      end

      before do
        allow(DhanHQ::Models::Funds).to receive(:fetch).and_return(mock_funds)
      end

      it "handles zero balances correctly" do
        live_balance.send(:refresh_cache)

        cache = live_balance.instance_variable_get(:@cache)
        expect(cache[:available]).to eq(0.0)
        expect(cache[:total]).to eq(0.0)
        expect(cache[:used]).to eq(0.0)
      end
    end
  end
end
