# frozen_string_literal: true

RSpec.describe ArcaConfig do
  it "exposes a semantic version" do
    expect(ArcaConfig::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
