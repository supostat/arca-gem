# frozen_string_literal: true

module ArcaConfig
  class Schema
    KEY_NAME_PATTERN = /\A[A-Z][A-Z0-9_]{0,127}\z/
    TYPES = %i[boolean integer string].freeze

    def initialize
      @types_by_key = {}
    end

    def declare(name, type)
      unless name.is_a?(String) && name.match?(KEY_NAME_PATTERN)
        raise DeclarationError, "invalid key name: #{name.inspect}"
      end
      raise DeclarationError, "unknown type #{type.inspect} for key #{name}" unless TYPES.include?(type)
      raise DeclarationError, "key #{name} is declared twice" if @types_by_key.key?(name)

      @types_by_key[name] = type
    end

    def type_of(name)
      @types_by_key.fetch(name) do
        raise UndeclaredKeyError, "key #{name.inspect} is not declared in ArcaConfig.configure"
      end
    end

    def key_names
      @types_by_key.keys
    end
  end
end
