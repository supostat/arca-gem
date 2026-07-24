# frozen_string_literal: true

RSpec.describe "I5: boot fail-fast" do
  it "fails the boot naming the key that resolves nowhere" do
    expect do
      ArcaConfig.configure do |config|
        config.app = "boss"
        config.instance = "dev2"
        config.key "ARCA_SPEC_MISSING_EVERYWHERE", :integer
      end
    end.to raise_error(ArcaConfig::BootValidationError, /ARCA_SPEC_MISSING_EVERYWHERE/)
  end

  it "counts garbage boot-ENV as unresolved for a typed key" do
    ENV["ARCA_SPEC_BAD_FLAG"] = "yes"

    expect do
      ArcaConfig.configure do |config|
        config.app = "boss"
        config.instance = "dev2"
        config.key "ARCA_SPEC_BAD_FLAG", :boolean
      end
    end.to raise_error(ArcaConfig::BootValidationError, /ARCA_SPEC_BAD_FLAG/)
  ensure
    ENV.delete("ARCA_SPEC_BAD_FLAG")
  end

  it "boots from Redis when boot-time ENV has nothing" do
    client = FakeRedisClient.new(values: { "arca:config:boss:dev2:ARCA_SPEC_REDIS_ONLY" => "true" })

    ArcaConfig.configure do |config|
      config.app = "boss"
      config.instance = "dev2"
      config.redis_client_factory = -> { client }
      config.key "ARCA_SPEC_REDIS_ONLY", :boolean
    end

    expect(ArcaConfig.enabled?("ARCA_SPEC_REDIS_ONLY")).to be(true)
  end
end
