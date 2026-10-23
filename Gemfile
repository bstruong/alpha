# frozen_string_literal: true

source "https://rubygems.org"

# Alpha — Headless LLM Evaluation & Qualification Harness
# Pure Ruby runtime dependencies: zero third-party gems (Ruby standard library only)
gemspec

group :development, :test do
  gem "rake", "~> 13.0"
  gem "minitest", "~> 5.20"
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "rubocop", require: false
end
