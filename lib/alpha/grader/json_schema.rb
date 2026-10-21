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
            detail: { error: "Missing output.txt in sandbox" }
          )
        end

        raw = File.read(output_file).strip
        # Strip potential <think>...</think> blocks and markdown json code fences
        cleaned = raw.gsub(%r{<think>.*?</think>}m, "").strip
        cleaned = cleaned.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "").strip

        parsed = JSON.parse(cleaned) rescue nil
        unless parsed.is_a?(Hash)
          return Result.new(
            name: "JsonSchema",
            pass: false,
            detail: { error: "Output is not valid JSON object", raw_output: raw.first(200) }
          )
        end

        required_keys = task.respond_to?(:required_json_keys) ? Array(task.required_json_keys) : []
        missing_keys = required_keys.reject { |k| parsed.key?(k.to_s) }

        # Check for non-null/non-empty values on required keys
        empty_keys = required_keys.select do |k|
          val = parsed[k.to_s]
          val.nil? || (val.respond_to?(:empty?) && val.empty?)
        end

        # Optional nested array object key checks (e.g., action_items: [task, owner, deadline, context])
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

        # Optional expected value assertions (e.g., urgency: "P1", is_threat: true)
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

        # Optional required markers / indicators in JSON content
        req_markers = task.respond_to?(:required_json_markers) ? Array(task.required_json_markers) : []
        missing_markers = req_markers.reject do |marker|
          cleaned.match?(Regexp.new(marker.to_s, Regexp::IGNORECASE))
        end

        # Optional false-positive guard patterns (denied in JSON output)
        denied_rules = task.respond_to?(:denied_json_patterns) && task.denied_json_patterns ? task.denied_json_patterns : {}
        false_positives = []
        denied_rules.each do |label, pattern|
          regex = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern.to_s, Regexp::IGNORECASE)
          if cleaned.match?(regex)
            false_positives << label.to_s
          end
        end

        passed = missing_keys.empty? &&
                 empty_keys.empty? &&
                 nested_errors.empty? &&
                 value_mismatches.empty? &&
                 missing_markers.empty? &&
                 false_positives.empty?

        detail = {
          passed: passed,
          keys_found: parsed.keys,
          missing_keys: missing_keys,
          empty_keys: empty_keys,
          nested_errors: nested_errors,
          value_mismatches: value_mismatches,
          missing_markers: missing_markers,
          false_positives: false_positives,
          parsed_sample: parsed
        }

        Result.new(name: "JsonSchema", pass: passed, detail: detail)
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
    end
  end
end
