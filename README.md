# arca-runtime-config

Typed runtime-configuration consumer for applications in the ARCA fleet. The gem reads
dynamic configuration that the fleet tooling mirrors into Redis, falls back to boot-time
environment variables when Redis cannot answer, and never requires an application restart
to observe a changed value.

The gem is a strict implementation of the ARCA Runtime-Config Consumer Contract
(`docs/CONTRACT.md`). When this README and the contract disagree, the contract wins.

## How configuration is delivered

Configuration reaches an application through exactly two channels:

- **static** — ordinary environment variables set at deploy time. A static value is
  immutable for the lifetime of a process.
- **dynamic** — the fleet tool writes the value to the deploy config store (the source of
  truth) and mirrors it into the stand's Redis (the delivery cache). A running process
  observes the change through Redis without a restart; any later restart boots with the
  same value from the environment.

Redis is a *cache of the environment truth*, not an override layer: when Redis and
boot-time ENV disagree, Redis is the fresher value and wins reads; when Redis is
unavailable or has no key, boot-time ENV is the correct fallback ("as deployed").

The consumer **never writes to Redis**. There is no write code path in this gem — the
Redis adapter exposes a single `get` method, and a named spec pins that invariant.

## Installation

Add the gem to your application's `Gemfile`:

```ruby
gem "arca-runtime-config"
```

Requirements: Ruby >= 3.0. The only runtime dependency is
[`redis-client`](https://github.com/redis-rb/redis-client).

## Configuration

Declare the key schema once at boot (for Rails, an initializer):

```ruby
ArcaConfig.configure do |config|
  config.redis_url = ENV["ARCA_CONFIG_REDIS_URL"] # absent => Redis-less degraded mode
  config.app       = "boss"
  config.instance  = "dev2"

  config.key "FEATURE1_ENABLED",            :boolean
  config.key "AUTO_LOGOUT_TIMEOUT_SECONDS", :integer
end
```

- `app` and `instance` form the gem's Redis namespace and must be lowercase slugs
  matching `[a-z0-9-]{1,64}`. The gem performs no discovery — both values are explicit
  deployment configuration.
- `redis_url` normally comes from an environment variable injected at deploy time (on
  dokku, `dokku redis:link` provides one). When it is absent the gem runs in degraded
  mode: every read serves the boot-time ENV value.
- `config.key NAME, TYPE` declares one key. `NAME` must match `[A-Z][A-Z0-9_]{0,127}`;
  `TYPE` is `:boolean`, `:integer` or `:string`. Declaring the same key twice, an invalid
  name, or an unknown type raises `ArcaConfig::DeclarationError`.
- The boot-time ENV value of every declared key is captured at declaration time. Later
  mutations of the process environment do not affect reads.

Optional settings:

| Setting | Default | Purpose |
| --- | --- | --- |
| `config.logger` | `Logger.new($stderr)` | Where failure-mode warnings go |
| `config.cache_ttl_seconds` | `5.0` | TTL of the per-process value cache |
| `config.redis_client_factory` | built from `redis_url` | Test seam: a callable returning a `RedisClient`-compatible object |

### Boot fail-fast

`ArcaConfig.configure` validates every declared key at the end of the block: each key must
resolve — parse to a valid value of its declared type — from Redis or from boot-time ENV.
A key that resolves nowhere fails the boot with `ArcaConfig::BootValidationError` naming
the key. Garbage in boot-time ENV (for example `FEATURE1_ENABLED=yes`) counts as
unresolved and fails the boot too.

Redis reachability is **not** required at boot: with Redis absent, unreachable or empty,
the application boots and serves values exactly "as deployed" from boot-time ENV.

## Reading values

```ruby
ArcaConfig.enabled?("FEATURE1_ENABLED")          # => true / false
ArcaConfig.fetch("AUTO_LOGOUT_TIMEOUT_SECONDS")  # => Integer
ArcaConfig.fetch("SOME_STRING_KEY")              # => String
```

- `fetch` returns the typed value of a declared key.
- `enabled?` is sugar for boolean keys; calling it on a non-boolean key raises
  `ArcaConfig::DeclarationError`.
- Reading a key that was not declared raises `ArcaConfig::UndeclaredKeyError`. That is a
  programming error, not a runtime condition — declare every key you read.

### The read chain

A read resolves through this chain, first hit wins:

```
test stub  →  request/job snapshot  →  per-process TTL cache (~5 s)  →  Redis GET  →  boot-time ENV
```

1. **Test stub** — active only inside an `ArcaConfig.stub` block (see below).
2. **Snapshot** — inside a wrapped web request or Sidekiq job, all reads return the
   values frozen at request/job start.
3. **TTL cache** — a thread-safe in-process cache bounds staleness: a flipped value is
   observed within one TTL (~5 seconds by default). There is no pub/sub in v1; the TTL is
   the propagation bound.
4. **Redis GET** of `arca:config:<app>:<instance>:<KEY>` on cache miss.
5. **Boot-time ENV** — when Redis is unreachable, the key is absent in Redis, or the
   Redis value is garbage.

### Value format

Every value — in Redis and in ENV alike — is a string in env format. One parser serves
both read paths:

| Declared type | Wire form | Parse rule |
| --- | --- | --- |
| `boolean` | exactly `"true"` or `"false"` | anything else is garbage → fallback |
| `integer` | decimal digits, optional leading `-` | anything else is garbage → fallback |
| `string` | the raw string | always valid |

The empty string is garbage for `boolean`/`integer` and a valid value for `string`.

### Failure modes

A broken flag flip must not take production down, so garbage never raises at read time:

| Condition | Behavior |
| --- | --- |
| Redis down at boot | boot proceeds; reads serve boot-time ENV |
| Redis becomes unreachable | one warning log, cool-down (no per-read connection storms), reads serve boot-time values |
| Redis recovers | the first read after cool-down resumes the normal chain |
| Garbage value in Redis | fallback + one warning per key per process; the fallback is cached for the normal TTL window |
| Key missing in Redis | silent fallback — a dynamic key may simply be unset yet |
| Key missing everywhere | impossible after boot (fail-fast checked it); at boot — `BootValidationError` |

"One warning" means once per failure episode per process, not once per read: a recovered
and re-broken connection logs again.

The fallback target is the *boot-resolved* value — the value each key resolved to at
`configure` time (from Redis or ENV, whichever answered). For the common case of a valid
ENV variable this is exactly the boot-time ENV value.

## Request and job snapshots

Within one web request (or one Sidekiq job) all reads of all keys return the values
snapshotted at request start — a value flip mid-request cannot change behavior
mid-request.

Rack (Rails: `config/application.rb` or `config.ru`):

```ruby
use ArcaConfig::RackMiddleware
```

Sidekiq (server middleware, in the Sidekiq initializer):

```ruby
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add ArcaConfig::SidekiqMiddleware
  end
end
```

Both middlewares activate a snapshot of all declared keys on entry and restore the
previous state in `ensure`, so an exception inside the request or job never leaks a stale
snapshot into the worker thread. Snapshots are fiber-local; nested snapshots restore
correctly.

## Concurrency and forking servers

- The Redis connection is created lazily on first read **after** process fork
  (Puma/Sidekiq fork workers; a connection inherited across fork is a defect). The reader
  detects a PID change and reconnects transparently.
- The TTL cache, the snapshot storage and the failure bookkeeping are thread-safe.

## Testing your application

The gem ships a test helper so consumer test suites do not invent their own mocking:

```ruby
ArcaConfig.stub("FEATURE1_ENABLED" => true) do
  # assertions for the enabled branch
end
```

- The stub bypasses Redis and ENV entirely and restores the prior state on block exit,
  including when the block raises.
- Values are *typed* Ruby values (`true`, `42`, `"text"`), not wire strings. A value of
  the wrong type raises `ArcaConfig::DeclarationError`; stubbing an undeclared key raises
  `ArcaConfig::UndeclaredKeyError`.
- Stubs nest — the innermost value wins and unwinds in order.
- Snapshots taken inside a stub block (e.g. through the middlewares) see the stubbed
  values.

## Errors

All errors inherit from `ArcaConfig::Error`:

| Class | Raised when |
| --- | --- |
| `ArcaConfig::DeclarationError` | invalid declaration, invalid slug, wrong stub value type, `enabled?` on a non-boolean key |
| `ArcaConfig::UndeclaredKeyError` | reading or stubbing a key absent from the declaration |
| `ArcaConfig::BootValidationError` | a declared key resolves neither from Redis nor from boot-time ENV at `configure` time |

Nothing else raises at read time by design.

## Out of scope (v1)

- **Pub/sub invalidation** — the ~5 s TTL bounds staleness sufficiently; adding pub/sub
  later will not change the public API.
- **Percentage rollout, actors, gradual rollout** — different product (e.g. Flipper);
  this gem is typed runtime config with env parity, nothing more.
- **Writing configuration** — all writes happen on the ARCA/fleet side.

## Development

```
bundle install
bundle exec rspec     # full suite
bundle exec rubocop   # style gate
```

The spec layout mirrors the contract: every invariant and every failure-mode row has a
named spec — `spec/invariants/i1_read_only_consumer_spec.rb` …
`i5_boot_fail_fast_spec.rb`, `spec/failure_modes/redis_down_at_boot_spec.rb` …
`key_missing_everywhere_spec.rb`. Tests need no live Redis: the client is replaced by
`spec/support/fake_redis_client.rb`, time by `spec/support/fake_clock.rb`.

Internal structure (one class per file under `lib/arca_config/`):

| File | Responsibility |
| --- | --- |
| `schema.rb` | key declarations, name/type validation, undeclared-key errors |
| `value_parser.rb` | the single env-format parser for both read paths |
| `configuration.rb` | the `configure` DSL object, boot-ENV capture, slug validation |
| `boot_validator.rb` | boot fail-fast: every declared key must resolve at `configure` time |
| `ttl_cache.rb` | thread-safe per-process cache, monotonic clock |
| `redis_reader.rb` | lazy post-fork `GET`-only Redis access, log-once + cool-down |
| `resolver.rb` | the cache → Redis → boot-value chain, garbage fallback |
| `snapshot.rb` | fiber-local frozen value set for requests and jobs |
| `rack_middleware.rb` / `sidekiq_middleware.rb` | snapshot activation per request / job |
| `test_helper.rb` | `ArcaConfig.stub` |
