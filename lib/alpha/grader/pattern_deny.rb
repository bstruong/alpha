# frozen_string_literal: true

require "json"

module Alpha
  module Grader
    # Deterministic pattern deny grader for privacy, PII scrubbing, and secret redaction.
    # Asserts that forbidden patterns (SSNs, emails, credit cards, API keys) do NOT appear
    # in the output, while required redaction markers or expected content DO appear.
    class PatternDeny < Base
      STANDARD_PII_PATTERNS = {
        "ssn" => /\b\d{3}-\d{2}-\d{4}\b/,
        "email" => /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/,
        "credit_card" => /\b(?:\d{4}[ -]?){3}\d{4}\b/,
        "api_key" => /\b(?:sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,})\b/
      }.freeze

      def call(sandbox:, task:, check_stability: false)
        output_file = File.join(sandbox.path, "output.txt")
        unless File.file?(output_file)
          return Result.new(
            name: "PatternDeny",
            pass: false,
            detail: { error: "Missing output.txt in sandbox" }
          )
        end

        content = File.read(output_file)

        # 1. Denied patterns (configured on task or standard PII defaults)
        denied_rules = if task.respond_to?(:denied_patterns) && task.denied_patterns && task.denied_patterns.any?
          task.denied_patterns
        else
          STANDARD_PII_PATTERNS
        end

        violations = []
        denied_rules.each do |label, pattern|
          regex = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern.to_s)
          matches = content.scan(regex)
          if matches.any?
            violations << { pattern: label.to_s, count: matches.size, matches: matches.first(3) }
          end
        end

        # 2. Required markers (e.g. [REDACTED], [SSN], etc.)
        required_markers = task.respond_to?(:required_markers) ? Array(task.required_markers) : []
        missing_markers = []
        required_markers.each do |marker|
          missing_markers << marker unless content.include?(marker)
        end

        passed = violations.empty? && missing_markers.empty? && !content.strip.empty?

        detail = {
          passed: passed,
          violations: violations,
          missing_markers: missing_markers,
          output_length: content.length,
          output_preview: content.lines.first(5).join
        }

        Result.new(name: "PatternDeny", pass: passed, detail: detail)
      end
    end
  end
end
