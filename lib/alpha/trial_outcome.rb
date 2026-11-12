# frozen_string_literal: true

module Alpha
  # Distinguishes infrastructure invalid trials from scored model failures.
  module TrialOutcome
    INFRA_EXIT_PATTERNS = [
      /\Aerror:/i,
      /connection refused/i,
      /failed to open tcp/i,
      /name or service not known/i,
      /http_error_5\d\d/i,
      /http_error_0/i,
      /\boom\b/i,
      /out of memory/i,
      /cuda/i,
      /inference.*(down|unreachable|unavailable)/i
    ].freeze

    module_function

    # Returns { scored:, invalid:, invalid_reason: }
    def classify(exit_reason:, timed_out:, agent_patch_empty:, grader_detail: nil)
      reason = exit_reason.to_s
      detail = grader_detail.is_a?(Hash) ? grader_detail : {}

      if infra_exit?(reason)
        return outcome(invalid: true, reason: "infra_exit:#{reason}")
      end

      if detail[:error].to_s.match?(/Missing output\.txt|sandbox|provision/i) && agent_patch_empty
        return outcome(invalid: true, reason: "sandbox_or_missing_output")
      end

      if timed_out && agent_patch_empty && reason != "tool_budget_exceeded"
        return outcome(invalid: true, reason: "timeout_without_work")
      end

      if reason.match?(/Command timed out/i) && agent_patch_empty
        return outcome(invalid: true, reason: "grader_infra_timeout")
      end

      outcome(invalid: false, reason: nil)
    end

    def infra_exit?(reason)
      INFRA_EXIT_PATTERNS.any? { |re| reason.match?(re) }
    end

    def outcome(invalid:, reason:)
      {
        invalid: invalid,
        scored: !invalid,
        invalid_reason: reason
      }
    end
    private_class_method :outcome
  end
end
