# frozen_string_literal: true

class FakeRedisClient
  attr_reader :values, :calls
  attr_accessor :error

  def initialize(values: {}, error: nil)
    @values = values
    @error = error
    @calls = []
  end

  def call(command, key)
    @calls << [command, key]
    raise @error if @error

    @values[key]
  end
end
