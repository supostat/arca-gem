# frozen_string_literal: true

require "logger"

module ArcaConfig
  class Configuration
    SLUG_PATTERN = /\A[a-z0-9-]{1,64}\z/

    attr_accessor :redis_url, :app, :instance, :logger, :redis_client_factory, :cache_ttl_seconds
    attr_reader :schema, :boot_env

    def initialize
      @schema = Schema.new
      @boot_env = {}
      @logger = Logger.new($stderr)
      @cache_ttl_seconds = TtlCache::DEFAULT_TTL_SECONDS
    end

    def key(name, type)
      schema.declare(name, type)
      boot_env[name] = ENV.fetch(name, nil)
    end

    def validate!
      validate_slug("app", app)
      validate_slug("instance", instance)
    end

    def redis_namespace
      "arca:config:#{app}:#{instance}:"
    end

    private

    def validate_slug(field, value)
      return if value.is_a?(String) && value.match?(SLUG_PATTERN)

      raise DeclarationError, "#{field} must be a lowercase slug matching [a-z0-9-]{1,64}, got #{value.inspect}"
    end
  end
end
