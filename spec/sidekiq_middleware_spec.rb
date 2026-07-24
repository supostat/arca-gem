# frozen_string_literal: true

RSpec.describe ArcaConfig::SidekiqMiddleware do
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

  it "freezes values for the whole job execution" do
    reads = []

    described_class.new.call(:worker, {}, "default") do
      reads << ArcaConfig.enabled?("FEATURE1_ENABLED")
      client.values[redis_key] = "false"
      reads << ArcaConfig.enabled?("FEATURE1_ENABLED")
    end

    expect(reads).to eq([true, true])
    expect(ArcaConfig.enabled?("FEATURE1_ENABLED")).to be(false)
  end

  it "clears the snapshot even when the job raises" do
    expect do
      described_class.new.call(:worker, {}, "default") { raise "job failed" }
    end.to raise_error("job failed")
    expect(ArcaConfig::Snapshot.active).to be_nil
  end
end
