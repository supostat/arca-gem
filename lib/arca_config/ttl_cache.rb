# frozen_string_literal: true

module ArcaConfig
  class TtlCache
    DEFAULT_TTL_SECONDS = 5.0

    Entry = Struct.new(:value, :deadline)

    def initialize(ttl_seconds: DEFAULT_TTL_SECONDS, clock: MONOTONIC_CLOCK)
      @ttl_seconds = ttl_seconds
      @clock = clock
      @entries = {}
      @mutex = Mutex.new
    end

    def fetch(key)
      @mutex.synchronize do
        entry = @entries[key]
        return entry.value if entry && entry.deadline > @clock.call
      end

      value = yield
      @mutex.synchronize { @entries[key] = Entry.new(value, @clock.call + @ttl_seconds) }
      value
    end
  end
end
