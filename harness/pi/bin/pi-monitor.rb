#!/usr/bin/env ruby
# frozen_string_literal: true

# Thin wrapper around the canonical Alpha gem monitor.
# Keep this file tiny so tool-budget CLI flags cannot drift from lib/.
ENV["PI_CODING_AGENT_DIR"] ||= File.expand_path("..", __dir__)

canonical = File.expand_path("../../../../lib/alpha/executor/pi_monitor.rb", __dir__)
unless File.file?(canonical)
  warn "Error: canonical pi_monitor.rb not found at #{canonical}"
  exit 1
end

load canonical
