# frozen_string_literal: true

require_relative "lib/arca_config/version"

Gem::Specification.new do |spec|
  spec.name = "arca-runtime-config"
  spec.version = ArcaConfig::VERSION
  spec.authors = ["JSMBARS"]
  spec.summary = "Typed runtime-config consumer for the ARCA fleet"
  spec.description = "Reads typed runtime configuration through a request snapshot, " \
                     "a per-process TTL cache, Redis and boot-time ENV, per docs/CONTRACT.md."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*.rb", "docs/CONTRACT.md", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "redis-client", ">= 0.19"

  spec.metadata["rubygems_mfa_required"] = "true"
end
