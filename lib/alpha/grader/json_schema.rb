# frozen_string_literal: true

require "json"

module Alpha
  module Grader
    # Deterministic JSON schema and structure grader for document extraction (OCR, receipts, invoices).
    # Asserts that output parses as valid JSON, contains required keys, and matches type constraints.
    class JsonSchema < Base
      def call(sandbox:, task:, check_stability: false)
        output_file = File.join(sandbox.path, "output.txt")
        unless File.file?(output_file)
          return Result.new(
            name: "JsonSchema",
            pass: false,
            credit: 0.0,
            checks: [ { name: "output_present", pass: false, required: true, points: 1 } ],
            detail: { error: "Missing output.txt in sandbox", format_error: true }
          )
        end

        raw = File.read(output_file).strip
        cleaned = raw.gsub(%r{<think>.*?</think>}m, "").strip
        cleaned = cleaned.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "").strip

        parsed = JSON.parse(cleaned) rescue nil
        unless parsed.is_a?(Hash)
          return Result.new(
            name: "JsonSchema",
            pass: false,
            credit: 0.0,
            checks: [ { name: "valid_json_object", pass: false, required: true, points: 1 } ],
            detail: { error: "Output is not valid JSON object", raw_output: raw[0, 200], format_error: true }
          )
        end

        checks = [ { name: "valid_json_object", pass: true, required: true, points: 1 } ]

        required_keys = task.respond_to?(:required_json_keys) ? Array(task.required_json_keys) : []
        missing_keys = required_keys.reject { |k| parsed.key?(k.to_s) }
        empty_keys = required_keys.select do |k|
          val = parsed[k.to_s]
          val.nil? || (val.respond_to?(:empty?) && val.empty?)
        end
        checks << {
          name: "required_keys",
          pass: missing_keys.empty? && empty_keys.empty?,
          required: true,
          points: 2
        }

        nested_rules = task.respond_to?(:nested_json_keys) && task.nested_json_keys ? task.nested_json_keys : {}
        nested_errors = []
        nested_rules.each do |array_key, child_keys|
          arr = parsed[array_key.to_s]
          if !arr.is_a?(Array) || arr.empty?
            nested_errors << "#{array_key} must be a non-empty array"
          else
            arr.each_with_index do |item, idx|
              unless item.is_a?(Hash)
                nested_errors << "#{array_key}[#{idx}] is not a JSON object"
                next
              end
              Array(child_keys).each do |ck|
                cval = item[ck.to_s]
                if !item.key?(ck.to_s) || cval.nil? || (cval.respond_to?(:empty?) && cval.empty?)
                  nested_errors << "#{array_key}[#{idx}] missing or empty key '#{ck}'"
                end
              end
            end
          end
        end
        if nested_rules.any?
          checks << { name: "nested_keys", pass: nested_errors.empty?, required: true, points: 1 }
        end

        expected_vals = task.respond_to?(:expected_json_values) && task.expected_json_values ? task.expected_json_values : {}
        value_mismatches = []
        expected_vals.each do |k, expected|
          actual = parsed[k.to_s]
          matched = if expected.is_a?(Array)
            expected.any? { |exp| values_match?(actual, exp) }
          else
            values_match?(actual, expected)
          end
          unless matched
            value_mismatches << { key: k.to_s, expected: expected, actual: actual }
          end
        end
        if expected_vals.any?
          checks << { name: "expected_values", pass: value_mismatches.empty?, required: true, points: 2 }
        end

        req_markers = task.respond_to?(:required_json_markers) ? Array(task.required_json_markers) : []
        missing_markers = req_markers.reject do |marker|
          cleaned.match?(Regexp.new(Regexp.escape(marker.to_s), Regexp::IGNORECASE)) ||
            cleaned.match?(Regexp.new(marker.to_s, Regexp::IGNORECASE))
        end
        if req_markers.any?
          checks << { name: "required_markers", pass: missing_markers.empty?, required: true, points: 1 }
        end

        optional_markers = task.respond_to?(:optional_json_markers) ? Array(task.optional_json_markers) : []
        optional_markers.each do |marker|
          ok = cleaned.match?(Regexp.new(marker.to_s, Regexp::IGNORECASE))
          checks << { name: "optional_marker:#{marker}", pass: ok, required: false, points: 1 }
        end

        denied_rules = task.respond_to?(:denied_json_patterns) && task.denied_json_patterns ? task.denied_json_patterns : {}
        false_positives = []
        denied_rules.each do |label, pattern|
          regex = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern.to_s, Regexp::IGNORECASE)
          if cleaned.match?(regex)
            false_positives << label.to_s
          end
        end
        if denied_rules.any?
          checks << { name: "denied_patterns", pass: false_positives.empty?, required: true, points: 2 }
        end

        money_meta = { checks: [], money_invariant: false, recon_break: false }
        if (task.respond_to?(:money_keys) && Array(task.money_keys).any?) ||
           (task.respond_to?(:recon) && task.recon)
          money_meta = Money.validate_parsed_money!(
            parsed,
            required_cent_keys: Array(task.money_keys),
            recon: task.recon
          )
          checks.concat(money_meta[:checks])
        end

        Array(task.respond_to?(:optional_checks) ? task.optional_checks : []).each do |spec|
          name = spec.is_a?(Hash) ? (spec["name"] || spec[:name]) : spec.to_s
          points = spec.is_a?(Hash) ? (spec["points"] || spec[:points] || 1) : 1
          checks << { name: "optional:#{name}", pass: true, required: false, points: points }
        end

        passed = Money.required_pass?(checks)
        credit = Money.credit_from_checks(checks)

        detail = {
          passed: passed,
          keys_found: parsed.keys,
          missing_keys: missing_keys,
          empty_keys: empty_keys,
          nested_errors: nested_errors,
          value_mismatches: value_mismatches,
          missing_markers: missing_markers,
          false_positives: false_positives,
          parsed_sample: parsed,
          money_invariant: money_meta[:money_invariant],
          recon_break: money_meta[:recon_break],
          abstain_fail: parsed["action"].to_s == "abstain" && !passed ? false : detail_abstain_fail(parsed, passed)
        }

        Result.new(name: "JsonSchema", pass: passed, credit: credit, checks: checks, detail: detail)
      end

      private
        def values_match?(actual, expected)
          return true if actual == expected
          return false if actual.nil?

          if expected.is_a?(String) && actual.is_a?(String)
            actual.strip.casecmp?(expected.strip)
          else
            actual.to_s.strip.casecmp?(expected.to_s.strip)
          end
        end

        def detail_abstain_fail(parsed, passed)
          return false if passed
          return true if parsed.key?("action") && parsed["action"].to_s != "abstain" &&
                         parsed["scores_status"].to_s == "none"

          false
        end
    end
  end
end
