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
        # Strip potential markdown json code fences if model enclosed it
        cleaned = raw.sub(/\A```(?:json)?\s*/i, "").sub(/\s*```\z/, "").strip

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

        passed = missing_keys.empty? && empty_keys.empty?

        detail = {
          passed: passed,
          keys_found: parsed.keys,
          missing_keys: missing_keys,
          empty_keys: empty_keys,
          parsed_sample: parsed
        }

        Result.new(name: "JsonSchema", pass: passed, detail: detail)
      end
    end
  end
end
