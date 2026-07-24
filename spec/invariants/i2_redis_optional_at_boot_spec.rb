# frozen_string_literal: true

RSpec.describe "I2: Redis is optional at boot" do
  around do |example|
    ENV["AUTO_LOGOUT_TIMEOUT_SECONDS"] = "900"
    example.run
  ensure
    ENV.delete("AUTO_LOGOUT_TIMEOUT_SECONDS")
  end

  it "boots and serves boot-time ENV with no Redis configured at all" do
    ArcaConfig.configure do |config|
      config.app = "boss"
      config.instance = "dev2"
      config.key "AUTO_LOGOUT_TIMEOUT_SECONDS", :integer
    end

    expect(ArcaConfig.fetch("AUTO_LOGOUT_TIMEOUT_SECONDS")).to eq(900)
  end

  it "boots and serves boot-time ENV when Redis is unreachable" do
    client = FakeRedisClient.new(error: RedisClient::CannotConnectError.new("connection refused"))

    ArcaConfig.configure do |config|
      config.app = "boss"
      config.instance = "dev2"
      config.redis_client_factory = -> { client }
      config.logger = Logger.new(IO::NULL)
      config.key "AUTO_LOGOUT_TIMEOUT_SECONDS", :integer
    end

    expect(ArcaConfig.fetch("AUTO_LOGOUT_TIMEOUT_SECONDS")).to eq(900)
  end
end
