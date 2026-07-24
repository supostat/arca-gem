# frozen_string_literal: true

RSpec.describe "Failure mode: key missing in Redis" do
  around do |example|
    ENV["AUTO_LOGOUT_TIMEOUT_SECONDS"] = "900"
    example.run
  ensure
    ENV.delete("AUTO_LOGOUT_TIMEOUT_SECONDS")
  end

  it "serves boot-time ENV silently" do
    client = FakeRedisClient.new
    log_output = StringIO.new

    ArcaConfig.configure do |config|
      config.app = "boss"
      config.instance = "dev2"
      config.redis_client_factory = -> { client }
      config.logger = Logger.new(log_output)
      config.key "AUTO_LOGOUT_TIMEOUT_SECONDS", :integer
    end

    expect(ArcaConfig.fetch("AUTO_LOGOUT_TIMEOUT_SECONDS")).to eq(900)
    expect(log_output.string).to be_empty
  end
end
