# frozen_string_literal: true

RSpec.describe "I3: garbage never raises" do
  it "falls back to the boot value and warns once per key per process" do
    schema = ArcaConfig::Schema.new
    schema.declare("FEATURE1_ENABLED", :boolean)
    reader = ArcaConfig::RedisReader.new(
      client_factory: -> { FakeRedisClient.new(values: { "arca:config:boss:dev2:FEATURE1_ENABLED" => "banana" }) },
      logger: Logger.new(IO::NULL)
    )
    log_output = StringIO.new
    resolver = ArcaConfig::Resolver.new(
      schema: schema,
      boot_values: { "FEATURE1_ENABLED" => false },
      redis_reader: reader,
      cache: ArcaConfig::TtlCache.new(ttl_seconds: 0.0, clock: FakeClock.new),
      logger: Logger.new(log_output),
      namespace: "arca:config:boss:dev2:"
    )

    expect { resolver.fetch("FEATURE1_ENABLED") }.not_to raise_error
    expect(resolver.fetch("FEATURE1_ENABLED")).to be(false)
    expect(log_output.string.scan("FEATURE1_ENABLED").size).to eq(1)
  end
end
