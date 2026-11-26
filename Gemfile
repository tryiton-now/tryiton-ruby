# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development do
  gem "minitest", "~> 5.0"
  gem "rake", ">= 12.0"
  # rbs (>= 3.5 for optional record keys) needs Ruby 3.1+. It only checks sig/,
  # so older Rubies skip it.
  gem "rbs", ">= 3.5", require: false if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.1")
end
