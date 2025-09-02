# frozen_string_literal: true

require "spec_helper"

RSpec.describe DhanScalper::State do
  let(:state) { described_class.new(symbols: ["NIFTY"], session_target: 1000.0, max_day_loss: 500.0) }

  it "changes status" do
    state.set_status(:paused)
    expect(state.status).to eq(:paused)
  end

  it "tracks session pnl" do
    state.add_session_pnl(100)
    state.add_session_pnl(-50)
    expect(state.pnl).to eq(50)
  end

  it "upserts subscriptions" do
    rec = { segment: "IDX", security_id: "1", symbol: "NIFTY", ltp: 10.0, ts: Time.now }
    state.upsert_idx_sub(rec)
    expect(state.subs_idx.size).to eq(1)
    rec2 = rec.merge(ltp: 11.0)
    state.upsert_idx_sub(rec2)
    expect(state.subs_idx.first[:ltp]).to eq(11.0)
  end

  it "replaces open positions and pushes closed ones" do
    state.replace_open!([{ symbol: "NIFTY", sid: "1" }])
    expect(state.open.size).to eq(1)
    state.push_closed!(symbol: "NIFTY", side: "BUY", reason: "TP", entry: 1, exit_price: 2, net: 10)
    expect(state.closed.size).to eq(1)
  end

  it "limits closed history" do
    35.times do |i|
      state.push_closed!(symbol: "S#{i}", side: "B", reason: "x", entry: 1, exit_price: 1, net: 0)
    end
    expect(state.closed.size).to eq(30)
  end
end
