# frozen_string_literal: true

RSpec.describe "Failure mode: Redis down at boot" do
  around do |example|
    ENV["FEATURE1_ENABLED"] = "true"
    example.run
  ensure
    ENV.delete("FEATURE1_ENABLED")
  end

  it "boots anyway and reads serve boot-time ENV" do
    client = FakeRedisClient.new(error: RedisClient::CannotConnectError.new("connection refused"))

    ArcaConfig.configure do |config|
      config.app = "boss"
      config.instance = "dev2"
      config.redis_client_factory = -> { client }
      config.logger = Logger.new(IO::NULL)
      config.key "FEATURE1_ENABLED", :boolean
    end

    expect(ArcaConfig.enabled?("FEATURE1_ENABLED")).to be(true)
  end
end
