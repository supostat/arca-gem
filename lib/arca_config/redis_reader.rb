# frozen_string_literal: true

require "redis-client"

module ArcaConfig
  class RedisReader
    UNAVAILABLE = Object.new.freeze
    COOLDOWN_SECONDS = 5.0

    def initialize(client_factory:, logger:, clock: MONOTONIC_CLOCK)
      @client_factory = client_factory
      @logger = logger
      @clock = clock
      @mutex = Mutex.new
      @client = nil
      @owner_pid = nil
      @cooldown_until = nil
      @failure_logged = false
    end

    def get(key)
      return UNAVAILABLE if @client_factory.nil?

      @mutex.synchronize do
        return UNAVAILABLE if cooling_down?

        read_current_value(key)
      end
    end

    private

    def read_current_value(key)
      value = connected_client.call("GET", key)
      @failure_logged = false
      value
    rescue RedisClient::Error => error
      enter_cooldown(error)
      UNAVAILABLE
    end

    def cooling_down?
      !@cooldown_until.nil? && @clock.call < @cooldown_until
    end

    def connected_client
      unless @client && @owner_pid == Process.pid
        @client = @client_factory.call
        @owner_pid = Process.pid
      end

      @client
    end

    def enter_cooldown(error)
      @cooldown_until = @clock.call + COOLDOWN_SECONDS
      return if @failure_logged

      @logger.warn("ArcaConfig: Redis unavailable (#{error.class}: #{error.message}); serving boot-time values")
      @failure_logged = true
    end
  end
end
