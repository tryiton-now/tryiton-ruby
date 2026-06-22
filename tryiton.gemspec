# frozen_string_literal: true

require_relative "lib/tryiton/version"

Gem::Specification.new do |spec|
  spec.name          = "tryiton"
  spec.version       = Tryiton::VERSION
  spec.authors       = ["TryItOn"]
  spec.summary       = "Official Ruby SDK for the TryItOn virtual try-on API."
  spec.description    = "Add photoreal clothing, accessory, hairstyle, and tattoo virtual try-on to your app."
  spec.homepage      = "https://docs.tryiton.now"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.6"

  spec.files         = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = ["lib"]

  spec.metadata = {
    "homepage_uri" => "https://tryiton.now",
    "documentation_uri" => "https://docs.tryiton.now",
    "source_code_uri" => "https://github.com/tryiton-now/tryiton-ruby",
    "bug_tracker_uri" => "https://github.com/tryiton-now/tryiton-ruby/issues",
  }
end
