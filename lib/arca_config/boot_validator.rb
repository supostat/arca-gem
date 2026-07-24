# frozen_string_literal: true

module ArcaConfig
  class BootValidator
    def initialize(schema:, boot_env:, redis_reader:, namespace:)
      @schema = schema
      @boot_env = boot_env
      @redis_reader = redis_reader
      @namespace = namespace
    end

    def boot_values
      @schema.key_names.to_h { |name| [name, resolve!(name)] }
    end

    private

    def resolve!(name)
      type = @schema.type_of(name)
      from_redis = redis_value(name, type)
      return from_redis unless from_redis.nil?

      from_env = env_value(name, type)
      return from_env unless from_env.nil?

      raise BootValidationError,
            "ArcaConfig key #{name} (#{type}) resolves neither from Redis nor from boot-time ENV"
    end

    def redis_value(name, type)
      raw_value = @redis_reader.get("#{@namespace}#{name}")
      return nil if raw_value.equal?(RedisReader::UNAVAILABLE) || raw_value.nil?

      valid_or_nil(ValueParser.parse(type, raw_value))
    end

    def env_value(name, type)
      raw_value = @boot_env[name]
      return nil if raw_value.nil?

      valid_or_nil(ValueParser.parse(type, raw_value))
    end

    def valid_or_nil(parsed)
      ValueParser.garbage?(parsed) ? nil : parsed
    end
  end
end
