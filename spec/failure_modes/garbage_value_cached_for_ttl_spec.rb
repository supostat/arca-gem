# frozen_string_literal: true

RSpec.describe "Failure mode: garbage value in Redis" do
  it "caches the fallback for the TTL window instead of re-fetching per read" do
    clock = FakeClock.new
    client = FakeRedisClient.new(values: { "arca:config:boss:dev2:FEATURE1_ENABLED" => "banana" })
    schema = ArcaConfig::Schema.new
    schema.declare("FEATURE1_ENABLED", :boolean)
    log_output = StringIO.new
    resolver = ArcaConfig::Resolver.new(
      schema: schema,
      boot_values: { "FEATURE1_ENABLED" => false },
      redis_reader: ArcaConfig::RedisReader.new(
        client_factory: -> { client },
        logger: Logger.new(IO::NULL),
        clock: clock
      ),
      cache: ArcaConfig::TtlCache.new(ttl_seconds: 5.0, clock: clock),
      logger: Logger.new(log_output),
      namespace: "arca:config:boss:dev2:"
    )

    3.times { expect(resolver.fetch("FEATURE1_ENABLED")).to be(false) }
    expect(client.calls.size).to eq(1)

    clock.advance(5.1)
    expect(resolver.fetch("FEATURE1_ENABLED")).to be(false)
    expect(client.calls.size).to eq(2)
    expect(log_output.string.scan("garbage").size).to eq(1)
  end
end
