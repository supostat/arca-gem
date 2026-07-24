# frozen_string_literal: true

module ArcaConfig
  module ValueParser
    GARBAGE = Object.new.freeze
    INTEGER_PATTERN = /\A-?\d+\z/

    class << self
      def parse(type, raw_value)
        case type
        when :boolean then parse_boolean(raw_value)
        when :integer then parse_integer(raw_value)
        when :string then raw_value
        else raise ArgumentError, "unknown declared type: #{type.inspect}"
        end
      end

      def garbage?(value)
        value.equal?(GARBAGE)
      end

      private

      def parse_boolean(raw_value)
        case raw_value
        when "true" then true
        when "false" then false
        else GARBAGE
        end
      end

      def parse_integer(raw_value)
        return GARBAGE unless raw_value.is_a?(String) && raw_value.match?(INTEGER_PATTERN)

        Integer(raw_value, 10)
      end
    end
  end
end
