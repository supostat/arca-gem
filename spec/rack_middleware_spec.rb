# frozen_string_literal: true

RSpec.describe ArcaConfig::RackMiddleware do
  let(:redis_key) { "arca:config:boss:dev2:FEATURE1_ENABLED" }
  let(:client) { FakeRedisClient.new(values: { redis_key => "true" }) }

  before do
    fake_client = client
    ArcaConfig.configure do |config|
      config.app = "boss"
      config.instance = "dev2"
      config.redis_client_factory = -> { fake_client }
      config.cache_ttl_seconds = 0.0
      config.key "FEATURE1_ENABLED", :boolean
    end
  end

  it "freezes values for the whole request even when Redis flips mid-request" do
    reads = []
    app = lambda do |_env|
      reads << ArcaConfig.enabled?("FEATURE1_ENABLED")
      client.values[redis_key] = "false"
      reads << ArcaConfig.enabled?("FEATURE1_ENABLED")
      [200, {}, ["ok"]]
    end

    status, = described_class.new(app).call({})

    expect(status).to eq(200)
    expect(reads).to eq([true, true])
    expect(ArcaConfig.enabled?("FEATURE1_ENABLED")).to be(false)
  end

  it "clears the snapshot even when the app raises" do
    app = ->(_env) { raise "boom" }

    expect { described_class.new(app).call({}) }.to raise_error("boom")
    expect(ArcaConfig::Snapshot.active).to be_nil
  end
end
