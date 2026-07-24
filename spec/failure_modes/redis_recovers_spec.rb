# frozen_string_literal: true

RSpec.describe "Failure mode: Redis recovers" do
  it "resumes the normal chain on the first read after cool-down" do
    client = FakeRedisClient.new(values: { "k" => "v" })
    clock = FakeClock.new
    log_output = StringIO.new
    reader = ArcaConfig::RedisReader.new(
      client_factory: -> { client },
      logger: Logger.new(log_output),
      clock: clock
    )

    client.error = RedisClient::ConnectionError.new("connection reset")
    expect(reader.get("k")).to be(ArcaConfig::RedisReader::UNAVAILABLE)

    client.error = nil
    clock.advance(ArcaConfig::RedisReader::COOLDOWN_SECONDS + 0.1)
    expect(reader.get("k")).to eq("v")
  end

  it "logs again on a new failure episode after recovery" do
    client = FakeRedisClient.new(values: { "k" => "v" })
    clock = FakeClock.new
    log_output = StringIO.new
    reader = ArcaConfig::RedisReader.new(
      client_factory: -> { client },
      logger: Logger.new(log_output),
      clock: clock
    )

    client.error = RedisClient::ConnectionError.new("first episode")
    reader.get("k")
    client.error = nil
    clock.advance(ArcaConfig::RedisReader::COOLDOWN_SECONDS + 0.1)
    reader.get("k")
    client.error = RedisClient::ConnectionError.new("second episode")
    clock.advance(ArcaConfig::RedisReader::COOLDOWN_SECONDS + 0.1)
    reader.get("k")

    expect(log_output.string.scan("Redis unavailable").size).to eq(2)
  end
end
