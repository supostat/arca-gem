# frozen_string_literal: true

RSpec.describe "ArcaConfig.stub" do
  let(:redis_key) { "arca:config:boss:dev2:FEATURE1_ENABLED" }
  let(:client) { FakeRedisClient.new(values: { redis_key => "false" }) }

  around do |example|
    ENV["FEATURE1_ENABLED"] = "false"
    ENV["AUTO_LOGOUT_TIMEOUT_SECONDS"] = "900"
    example.run
  ensure
    ENV.delete("FEATURE1_ENABLED")
    ENV.delete("AUTO_LOGOUT_TIMEOUT_SECONDS")
  end

  before do
    fake_client = client
    ArcaConfig.configure do |config|
      config.app = "boss"
      config.instance = "dev2"
      config.redis_client_factory = -> { fake_client }
      config.cache_ttl_seconds = 0.0
      config.key "FEATURE1_ENABLED", :boolean
      config.key "AUTO_LOGOUT_TIMEOUT_SECONDS", :integer
    end
  end

  it "serves the stubbed typed value inside the block" do
    ArcaConfig.stub("FEATURE1_ENABLED" => true, "AUTO_LOGOUT_TIMEOUT_SECONDS" => 60) do
      expect(ArcaConfig.enabled?("FEATURE1_ENABLED")).to be(true)
      expect(ArcaConfig.fetch("AUTO_LOGOUT_TIMEOUT_SECONDS")).to eq(60)
    end
  end

  it "bypasses Redis and ENV entirely" do
    client.calls.clear

    ArcaConfig.stub("FEATURE1_ENABLED" => true) do
      expect(ArcaConfig.enabled?("FEATURE1_ENABLED")).to be(true)
    end

    expect(client.calls).to be_empty
  end

  it "restores the prior state on block exit" do
    ArcaConfig.stub("FEATURE1_ENABLED" => true) { nil }

    expect(ArcaConfig.enabled?("FEATURE1_ENABLED")).to be(false)
  end

  it "restores the prior state when the block raises" do
    expect do
      ArcaConfig.stub("FEATURE1_ENABLED" => true) { raise "assertion failed" }
    end.to raise_error("assertion failed")

    expect(ArcaConfig.enabled?("FEATURE1_ENABLED")).to be(false)
  end

  it "raises on stubbing an undeclared key" do
    expect do
      ArcaConfig.stub("NOT_DECLARED" => true) { nil }
    end.to raise_error(ArcaConfig::UndeclaredKeyError)
  end

  it "rejects a stub value of the wrong type" do
    expect do
      ArcaConfig.stub("FEATURE1_ENABLED" => "true") { nil }
    end.to raise_error(ArcaConfig::DeclarationError, /must be a boolean/)
  end

  it "supports nesting: innermost wins and unwinds in order" do
    ArcaConfig.stub("AUTO_LOGOUT_TIMEOUT_SECONDS" => 60) do
      ArcaConfig.stub("AUTO_LOGOUT_TIMEOUT_SECONDS" => 30) do
        expect(ArcaConfig.fetch("AUTO_LOGOUT_TIMEOUT_SECONDS")).to eq(30)
      end
      expect(ArcaConfig.fetch("AUTO_LOGOUT_TIMEOUT_SECONDS")).to eq(60)
    end
    expect(ArcaConfig.fetch("AUTO_LOGOUT_TIMEOUT_SECONDS")).to eq(900)
  end

  it "feeds stubbed values into snapshots taken inside the block" do
    ArcaConfig.stub("FEATURE1_ENABLED" => true) do
      ArcaConfig.with_snapshot do
        expect(ArcaConfig.enabled?("FEATURE1_ENABLED")).to be(true)
      end
    end
  end
end
