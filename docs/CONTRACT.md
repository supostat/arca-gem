# ARCA Runtime-Config Consumer Contract (v1)

This document is the complete interface between ARCA's runtime-config delivery and the Ruby
consumer gem. The gem is implemented in a SEPARATE repository against this document alone —
no access to ARCA source code is required or assumed. Everything a conforming implementation
needs is stated here; if something is missing, that is a defect of this document, not an
invitation to read ARCA internals.

## 1. Delivery model (context, normative for reads)

Configuration reaches a consumer application through exactly two channels:

- **static** — ordinary environment variables set at deploy time (`dokku config:set`, restart).
  A static value is immutable for the lifetime of a process.
- **dynamic** — the subject of this contract. The fleet tool writes the value to the dokku
  config store with `--no-restart` (the source of truth) and then mirrors it into the stand's
  Redis (the delivery cache). A running process observes the change through Redis without a
  restart; any later restart boots with the same value from env.

Consequences the gem MUST honor:

- Redis is a **cache of the env truth**, not an override layer. When Redis and boot-time ENV
  disagree, Redis is the FRESHER value and wins reads; when Redis is unavailable or has no
  key, boot-time ENV is the correct fallback ("as deployed").
- The consumer **NEVER writes Redis** — see invariant I1.
- Reconciliation of env↔Redis drift is the fleet's job, never the consumer's.

## 2. Redis key format

```
arca:config:<app>:<instance>:<KEY>
```

- `<app>`, `<instance>` — lowercase slugs matching `[a-z0-9-]{1,64}` (e.g. `boss`, `dev2`).
- `<KEY>` — the variable name, matching `[A-Z][A-Z0-9_]{0,127}` (e.g. `FEATURE1_ENABLED`).
- The gem's **namespace** is the `<app>:<instance>` pair. It is explicit configuration of the
  gem (two values the deployer knows); the gem performs no discovery.

Example: `arca:config:boss:dev2:FEATURE1_ENABLED`.

## 3. Value serialization

Every value — in Redis and in ENV alike — is a **string in env format**. One parser serves
both read paths; there is no Redis-specific encoding.

| Declared type | Wire form                             | Parse rule                                      |
| ------------- | ------------------------------------- | ----------------------------------------------- |
| `boolean`     | exactly `"true"` or `"false"`         | anything else is garbage → fallback (I3)        |
| `integer`     | decimal digits, optional leading `-`  | anything else is garbage → fallback (I3)        |
| `string`      | the raw string                        | always valid                                    |

Empty string is garbage for `boolean`/`integer` and a valid value for `string`.

## 4. Gem configuration (boot-time declaration)

The gem exposes exactly one way to use it: a boot-time declaration of the key schema, then
typed reads. Illustrative (naming is the implementor's; semantics are normative):

```ruby
ArcaConfig.configure do |c|
  c.redis_url = ENV["ARCA_CONFIG_REDIS_URL"]   # absent => Redis-less degraded mode
  c.app       = "boss"
  c.instance  = "dev2"

  c.key "FEATURE1_ENABLED",            :boolean
  c.key "AUTO_LOGOUT_TIMEOUT_SECONDS", :integer
end

ArcaConfig.enabled?("FEATURE1_ENABLED")          # => true / false
ArcaConfig.fetch("AUTO_LOGOUT_TIMEOUT_SECONDS")  # => Integer
```

- `redis_url` comes from an environment variable provided at deploy time (on dokku,
  `dokku redis:link` injects one; the exact variable name is deployment configuration).
- Reading a key that was not declared raises an error — that is a programming error, not a
  runtime condition (I4).
- At boot, every declared key MUST resolve from at least boot-time ENV; a key resolvable
  nowhere fails the boot loudly (I5). Redis reachability is NOT required at boot (I2).

## 5. Read semantics

A read of a declared key resolves through this chain, first hit wins:

```
request-scoped snapshot  →  per-process TTL cache (~5 s)  →  Redis GET  →  boot-time ENV
```

1. **Request-scoped snapshot.** Within one web request all reads of all keys return the values
   snapshotted at request start (Rack middleware). A value change mid-request MUST NOT change
   behavior mid-request. Background jobs (e.g. Sidekiq) get the same guarantee per job
   execution via a per-job snapshot.
2. **Per-process TTL cache.** Outside a snapshot (and to fill one), reads go through a
   thread-safe in-process cache with a TTL of ~5 seconds. The TTL bounds staleness: a flipped
   value is observed within one TTL. No pub/sub in v1 (see §8).
3. **Redis GET** of `arca:config:<app>:<instance>:<KEY>` on cache miss.
4. **Boot-time ENV** — the value of `ENV[<KEY>]` captured at process start — when Redis is
   unreachable, the key is absent in Redis, or the Redis value is garbage (§3).

Concurrency requirements:

- The Redis connection is created lazily AFTER process fork (Puma/Sidekiq fork workers;
  a connection inherited across fork is a defect).
- The cache and snapshot structures are thread-safe.

## 6. Invariants

- **I1 — read-only consumer.** The gem contains NO code path that writes to Redis. Its
  boot-time ENV is a process-start snapshot; writing it anywhere would overwrite fresher
  values. This is a structural invariant, not a configuration default.
- **I2 — Redis optional at boot.** The application boots and serves with Redis absent,
  unreachable, or empty; behavior degrades exactly to "as deployed" (boot-time ENV).
- **I3 — garbage never raises.** A value that fails its type's parse rule falls back to
  boot-time ENV and logs ONE warning; it never raises at read time. A broken flag flip must
  not take production down.
- **I4 — undeclared key is an error.** Reading a key absent from the declaration raises.
- **I5 — boot fail-fast.** A declared key that resolves neither from Redis nor from boot-time
  ENV at declaration time fails the boot with a clear message naming the key. "Resolves" means
  "parses to a valid value of the declared type" — boot-time ENV holding garbage for a
  `boolean`/`integer` key counts as unresolved and fails the boot.

## 7. Failure modes

| Condition                    | Behavior                                                                 |
| ---------------------------- | ------------------------------------------------------------------------ |
| Redis down at boot           | boot proceeds (I2); reads serve boot-time ENV                            |
| Redis becomes unreachable    | log ONCE, enter cool-down (no per-read connection storms), serve ENV     |
| Redis recovers               | next read after cool-down resumes the normal chain                       |
| Garbage value in Redis       | ENV fallback + one warning log per key per process (I3); the fallback result is cached for the normal TTL window (no per-read re-fetch) |
| Key missing in Redis         | ENV fallback, silent — a dynamic key may simply be unset yet             |
| Key missing everywhere       | impossible after boot (I5 checked it); at boot — fail-fast               |

"Log once" means once per failure episode per process, not once per read.

## 8. Deliberately out of scope (v1)

- **Pub/sub invalidation.** The ~5 s TTL bounds staleness sufficiently; adding pub/sub later
  MUST NOT change the public API of §4-5.
- **Percentage rollout, actors, gradual rollout.** Different product (e.g. Flipper); this gem
  is typed runtime config with env parity, nothing more.
- **Writing configuration.** All writes happen on the ARCA/fleet side.

## 9. Test support (required in v1)

The gem ships a test helper that stubs declared keys for the duration of a block, so consumer
test suites do not each invent their own mocking:

```ruby
ArcaConfig.stub("FEATURE1_ENABLED" => true) do
  # assertions for the enabled branch
end
```

The helper bypasses Redis and ENV entirely and restores prior state on block exit.
