# frozen_string_literal: true

module ArcaConfig
  module TestHelper
    def stub(overrides)
      validate_stub_overrides(overrides)
      previous = @stubbed_values
      @stubbed_values = (previous || {}).merge(overrides)
      yield
    ensure
      @stubbed_values = previous
    end

    private

    def validate_stub_overrides(overrides)
      schema = active_configuration.schema
      overrides.each do |name, value|
        validate_stub_value(name, schema.type_of(name), value)
      end
    end

    def validate_stub_value(name, type, value)
      valid = case type
              when :boolean then [true, false].include?(value)
              when :integer then value.is_a?(Integer)
              when :string then value.is_a?(String)
              end
      return if valid

      raise DeclarationError, "stub value for #{name} must be a #{type}, got #{value.inspect}"
    end
  end
end
