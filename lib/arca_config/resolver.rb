# frozen_string_literal: true

require "set"

module ArcaConfig
  class Resolver
    def initialize(schema:, boot_values:, redis_reader:, cache:, logger:, namespace:)
      @schema = schema
      @boot_values = boot_values
      @redis_reader = redis_reader
      @cache = cache
      @logger = logger
      @namespace = namespace
      @garbage_warned_keys = Set.new
      @garbage_warned_mutex = Mutex.new
    end

    def fetch(name)
      type = @schema.type_of(name)
      @cache.fetch(name) { resolve(name, type) }
    end

    private

    def resolve(name, type)
      raw_value = @redis_reader.get("#{@namespace}#{name}")
      return @boot_values.fetch(name) if raw_value.equal?(RedisReader::UNAVAILABLE) || raw_value.nil?

      parsed = ValueParser.parse(type, raw_value)
      return parsed unless ValueParser.garbage?(parsed)

      warn_garbage_once(name, type, raw_value)
      @boot_values.fetch(name)
    end

    def warn_garbage_once(name, type, raw_value)
      @garbage_warned_mutex.synchronize do
        return if @garbage_warned_keys.include?(name)

        @garbage_warned_keys << name
        @logger.warn(
          "ArcaConfig: key #{name} carries a garbage #{type} value #{raw_value.inspect} in Redis; " \
          "serving boot-time value"
        )
      end
    end
  end
end
