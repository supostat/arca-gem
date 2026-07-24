# frozen_string_literal: true

class FakeClock
  def initialize(now = 0.0)
    @now = now
  end

  def call
    @now
  end

  def advance(seconds)
    @now += seconds
  end
end
