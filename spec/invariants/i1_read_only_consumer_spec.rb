# frozen_string_literal: true

RSpec.describe "I1: read-only consumer" do
  it "exposes only a read method on the Redis path" do
    expect(ArcaConfig::RedisReader.public_instance_methods(false)).to contain_exactly(:get)
  end

  it "sends only GET commands over a full configure-and-read cycle" do
    client = FakeRedisClient.new(values: { "arca:config:boss:dev2:FEATURE1_ENABLED" => "true" })

    ArcaConfig.configure do |config|
      config.app = "boss"
      config.instance = "dev2"
      config.redis_client_factory = -> { client }
      config.key "FEATURE1_ENABLED", :boolean
    end

    expect(ArcaConfig.enabled?("FEATURE1_ENABLED")).to be(true)
    expect(client.calls).not_to be_empty
    expect(client.calls.map(&:first).uniq).to eq(["GET"])
  end
end
