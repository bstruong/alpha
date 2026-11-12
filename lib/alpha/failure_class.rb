# frozen_string_literal: true

module Alpha
  # Deterministic failure taxonomy for scored trials (never use an LLM judge).
  module FailureClass
    VALUES = %w[
      none noop wrong_file partial broke_suite tool_thrash format
      hallucinated_api abstain_fail money_invariant recon_break infra unknown
    ].freeze

    module_function

    def classify(pass:, invalid:, invalid_reason: nil, agent_patch_empty: false,
                 exit_reason: nil, timed_out: false, tool_budget_exceeded: false,
                 grader_detail: nil, credit: nil)
      return "infra" if invalid
      return "none" if pass

      detail = grader_detail.is_a?(Hash) ? grader_detail : {}

      return "money_invariant" if detail[:money_invariant] || detail[:failure_class] == "money_invariant"
      return "recon_break" if detail[:recon_break] || detail[:failure_class] == "recon_break"
      return "abstain_fail" if detail[:abstain_fail] || detail[:failure_class] == "abstain_fail"

      if detail[:error].to_s.match?(/not valid JSON|Missing output/i) || detail[:format_error]
        return "format"
      end

      drifted = Array(detail[:drifted])
      return "wrong_file" if drifted.any?

      if tool_budget_exceeded || (timed_out && exit_reason.to_s == "tool_budget_exceeded")
        return "tool_thrash"
      end

      return "noop" if agent_patch_empty && !detail_has_model_output?(detail)

      if detail[:rails_test] == false || detail[:rspec_test] == false
        return "broke_suite" if detail[:verifier_ok] != false
      end

      if credit.is_a?(Numeric) && credit.positive? && credit < 1.0
        return "partial"
      end

      if Array(detail[:violations]).any? || Array(detail[:false_positives]).any?
        return "hallucinated_api" if detail[:hallucinated_api]
      end

      if Array(detail[:missing_keys]).any? || Array(detail[:missing_markers]).any? ||
         Array(detail[:value_mismatches]).any? || Array(detail[:nested_errors]).any?
        return "partial" if detail_has_model_output?(detail)

        return "format"
      end

      return "noop" if agent_patch_empty

      "unknown"
    end

    def detail_has_model_output?(detail)
      return true if detail[:parsed_sample].is_a?(Hash) && detail[:parsed_sample].any?
      return true if detail[:output_length].to_i.positive?
      return true if detail[:keys_found].is_a?(Array) && detail[:keys_found].any?

      false
    end
    private_class_method :detail_has_model_output?
  end
end
