# frozen_string_literal: true

require_relative "lib/alpha/version"

Gem::Specification.new do |spec|
  spec.name          = "alpha-eval"
  spec.version       = Alpha::VERSION
  spec.authors       = ["Brian Truong"]
  spec.email         = ["btruong@users.noreply.github.com"]
  spec.summary       = "Headless evaluation and benchmarking harness for LLMs and coding agents"
  spec.description   = "Deterministic scenario runner, multi-turn repair supervisor, and qualification engine for evaluating local and cloud LLMs."
  spec.homepage      = "https://github.com/bstruong/alpha"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  # Strict packaging allowlist: package only the engine mechanism, never private homelab scenarios/presets
  spec.files = Dir["lib/**/*.rb", "bin/alpha", "README.md", "CONVENTIONS.md"]
  spec.bindir        = "bin"
  spec.executables   = ["alpha"]
  spec.require_paths = ["lib"]

  # Zero production runtime dependencies (Ruby standard library only)
end
