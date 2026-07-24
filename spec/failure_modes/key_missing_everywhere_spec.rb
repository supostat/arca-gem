# frozen_string_literal: true

RSpec.describe "Failure mode: key missing everywhere" do
  it "is impossible after boot: configure fails fast naming the key" do
    client = FakeRedisClient.new

    expect do
      ArcaConfig.configure do |config|
        config.app = "boss"
        config.instance = "dev2"
        config.redis_client_factory = -> { client }
        config.key "ARCA_SPEC_ABSENT_KEY", :string
      end
    end.to raise_error(ArcaConfig::BootValidationError, /ARCA_SPEC_ABSENT_KEY/)
  end
end
