# frozen_string_literal: true

require_relative "arca_config/version"
require_relative "arca_config/value_parser"
require_relative "arca_config/schema"
require_relative "arca_config/configuration"
require_relative "arca_config/ttl_cache"
require_relative "arca_config/redis_reader"
require_relative "arca_config/boot_validator"
require_relative "arca_config/resolver"
require_relative "arca_config/snapshot"
require_relative "arca_config/rack_middleware"
require_relative "arca_config/sidekiq_middleware"
require_relative "arca_config/test_helper"

module ArcaConfig
  class Error < StandardError; end
  class DeclarationError < Error; end
  class UndeclaredKeyError < Error; end
  class BootValidationError < Error; end

  MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

  extend TestHelper

  class << self
    def configure
      configuration = Configuration.new
      yield configuration
      configuration.validate!
      @resolver = build_resolver(configuration)
      @configuration = configuration
      nil
    end

    def fetch(key_name)
      stubbed = @stubbed_values
      return stubbed.fetch(key_name) if stubbed&.key?(key_name)

      snapshot = Snapshot.active
      return snapshot_value(snapshot, key_name) if snapshot

      active_resolver.fetch(key_name)
    end

    def with_snapshot
      previous = Snapshot.active
      Snapshot.activate(current_values)
      yield
    ensure
      Snapshot.restore(previous)
    end

    def enabled?(key_name)
      type = active_configuration.schema.type_of(key_name)
      unless type == :boolean
        raise DeclarationError, "enabled? requires a boolean key, #{key_name} is declared as #{type}"
      end

      fetch(key_name)
    end

    private

    def snapshot_value(snapshot, key_name)
      active_configuration.schema.type_of(key_name)
      snapshot.value_for(key_name)
    end

    def current_values
      active_configuration.schema.key_names.to_h { |name| [name, fetch(name)] }
    end

    def active_configuration
      @configuration || raise(Error, "ArcaConfig.configure has not been called")
    end

    def active_resolver
      @resolver || raise(Error, "ArcaConfig.configure has not been called")
    end

    def build_resolver(configuration)
      reader = RedisReader.new(client_factory: build_client_factory(configuration), logger: configuration.logger)
      namespace = configuration.redis_namespace
      boot_values = BootValidator.new(schema: configuration.schema, boot_env: configuration.boot_env,
                                      redis_reader: reader, namespace: namespace).boot_values
      Resolver.new(schema: configuration.schema, boot_values: boot_values, redis_reader: reader,
                   cache: TtlCache.new(ttl_seconds: configuration.cache_ttl_seconds),
                   logger: configuration.logger, namespace: namespace)
    end

    def build_client_factory(configuration)
      return configuration.redis_client_factory if configuration.redis_client_factory

      redis_url = configuration.redis_url
      return nil if redis_url.nil?

      -> { RedisClient.config(url: redis_url).new_client }
    end
  end
end
