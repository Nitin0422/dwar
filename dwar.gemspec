# frozen_string_literal: true

require_relative "lib/dwar/version"

Gem::Specification.new do |spec|
  spec.name = "dwar"
  spec.version = Dwar::VERSION
  spec.authors = ["Nitin Tandukar"]
  spec.summary = "Managed feature flags for Rails: enable/disable, deterministic percentage rollouts, and group-based targeting."
  spec.description = "A reusable, open-source, mountable Rails engine that gives any Rails application managed feature flags - full enable/disable, deterministic percentage rollouts, and group-based user targeting - administered through a server-rendered Rails-Admin-style web UI and queried through a simple developer API (Dwar.enabled?)."
  spec.homepage = "https://github.com/Nitin0422/dwar"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*", "app/**/*", "db/**/*", "LICENSE.txt"] }
  spec.require_paths = ["lib"]
  spec.add_dependency "rails", ">= 7.1"
  spec.metadata = {"homepage_uri" => "https://github.com/Nitin0422/dwar", "source_code_uri" => "https://github.com/Nitin0422/dwar", "rubygems_mfa_required" => "true"}
end
