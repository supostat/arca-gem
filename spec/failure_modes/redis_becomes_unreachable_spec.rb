# frozen_string_literal: true

RSpec.describe "Failure mode: Redis becomes unreachable" do
  it "logs once, enters cool-down and stops hammering the connection" do
    client = FakeRedisClient.new(values: { "k" => "v" })
    clock = FakeClock.new
    log_output = StringIO.new
    reader = ArcaConfig::RedisReader.new(
      client_factory: -> { client },
      logger: Logger.new(log_output),
      clock: clock
    )

    expect(reader.get("k")).to eq("v")

    client.error = RedisClient::ConnectionError.new("connection reset")
    expect(reader.get("k")).to be(ArcaConfig::RedisReader::UNAVAILABLE)

    attempts_after_failure = client.calls.size
    expect(reader.get("k")).to be(ArcaConfig::RedisReader::UNAVAILABLE)
    expect(reader.get("k")).to be(ArcaConfig::RedisReader::UNAVAILABLE)
    expect(client.calls.size).to eq(attempts_after_failure)
    expect(log_output.string.scan("Redis unavailable").size).to eq(1)
  end
end
