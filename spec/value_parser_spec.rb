# frozen_string_literal: true

RSpec.describe ArcaConfig::ValueParser do
  describe "boolean" do
    it "parses exactly \"true\"" do
      expect(described_class.parse(:boolean, "true")).to be(true)
    end

    it "parses exactly \"false\"" do
      expect(described_class.parse(:boolean, "false")).to be(false)
    end

    it "treats any other string as garbage" do
      %w[TRUE True 1 yes on].each do |raw|
        expect(described_class.parse(:boolean, raw)).to be(ArcaConfig::ValueParser::GARBAGE)
      end
    end

    it "treats the empty string as garbage" do
      expect(described_class.parse(:boolean, "")).to be(ArcaConfig::ValueParser::GARBAGE)
    end
  end

  describe "integer" do
    it "parses decimal digits" do
      expect(described_class.parse(:integer, "42")).to eq(42)
    end

    it "parses an optional leading minus" do
      expect(described_class.parse(:integer, "-7")).to eq(-7)
    end

    it "parses leading zeros as decimal" do
      expect(described_class.parse(:integer, "007")).to eq(7)
    end

    it "treats non-decimal strings as garbage" do
      ["1.5", "abc", " 1", "+1", "0x10"].each do |raw|
        expect(described_class.parse(:integer, raw)).to be(ArcaConfig::ValueParser::GARBAGE)
      end
    end

    it "treats the empty string as garbage" do
      expect(described_class.parse(:integer, "")).to be(ArcaConfig::ValueParser::GARBAGE)
    end
  end

  describe "string" do
    it "returns the raw string" do
      expect(described_class.parse(:string, "any value")).to eq("any value")
    end

    it "keeps the empty string as a valid value" do
      expect(described_class.parse(:string, "")).to eq("")
    end
  end

  it "flags garbage only through the sentinel" do
    expect(described_class.garbage?(described_class.parse(:boolean, "nope"))).to be(true)
    expect(described_class.garbage?(described_class.parse(:boolean, "true"))).to be(false)
  end
end
