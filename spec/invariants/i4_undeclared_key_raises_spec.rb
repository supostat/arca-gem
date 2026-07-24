# frozen_string_literal: true

RSpec.describe "I4: undeclared key is an error" do
  around do |example|
    ENV["FEATURE1_ENABLED"] = "true"
    example.run
  ensure
    ENV.delete("FEATURE1_ENABLED")
  end

  before do
    ArcaConfig.configure do |config|
      config.app = "boss"
      config.instance = "dev2"
      config.key "FEATURE1_ENABLED", :boolean
    end
  end

  it "raises on fetch of an undeclared key" do
    expect { ArcaConfig.fetch("NOT_DECLARED") }.to raise_error(ArcaConfig::UndeclaredKeyError)
  end

  it "raises on enabled? of an undeclared key" do
    expect { ArcaConfig.enabled?("NOT_DECLARED") }.to raise_error(ArcaConfig::UndeclaredKeyError)
  end

  it "rejects declaring a key with an invalid name" do
    expect do
      ArcaConfig.configure { |config| config.key "lower_case", :boolean }
    end.to raise_error(ArcaConfig::DeclarationError)
  end

  it "reads a declared key normally" do
    expect(ArcaConfig.enabled?("FEATURE1_ENABLED")).to be(true)
  end
end
