# frozen_string_literal: true

module ArcaConfig
  class Snapshot
    STORAGE_KEY = :arca_config_snapshot

    class << self
      def activate(values)
        Thread.current[STORAGE_KEY] = new(values)
      end

      def restore(snapshot)
        Thread.current[STORAGE_KEY] = snapshot
      end

      def active
        Thread.current[STORAGE_KEY]
      end
    end

    def initialize(values)
      @values = values.freeze
    end

    def value_for(name)
      @values.fetch(name)
    end
  end
end
