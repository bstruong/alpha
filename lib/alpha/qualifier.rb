# frozen_string_literal: true

module Alpha
  # Deterministic Pass@1 qualification against a scenario's configured thresholds.
  class Qualifier
    Result = Data.define(
      :qualified,
      :role,
      :scenario_id,
      :gate_pass_at_1,
      :graded_pass_at_1,
      :gate_threshold,
      :graded_threshold,
      :reason
    )

    def self.evaluate(summary, scenario: nil, role: nil)
      scenario_id = summary["scenario"].to_s
      scenario ||= begin
        Scenario.load(scenario_id)
      rescue ArgumentError
        nil
      end

      target_role = role || scenario&.role || infer_role(scenario_id)
      thresholds = scenario&.qualification || {
        gate_pass_at_1: 1.0,
        graded_pass_at_1: (target_role == "triager" ? 0.75 : 0.70)
      }
      gate_threshold = thresholds[:gate_pass_at_1].to_f
      graded_threshold = thresholds[:graded_pass_at_1].to_f

      tasks = Array(summary["tasks"])
      gate_rate = pass_at_1_rate(tasks, kind: "gate")
      graded_rate = pass_at_1_rate(tasks, kind: "graded")

      reasons = []
      reasons << "gate Pass@1 #{format_rate(gate_rate)} < #{format_rate(gate_threshold)}" if gate_rate < gate_threshold
      reasons << "graded Pass@1 #{format_rate(graded_rate)} < #{format_rate(graded_threshold)}" if graded_rate < graded_threshold

      Result.new(
        qualified: reasons.empty?,
        role: target_role,
        scenario_id: scenario_id,
        gate_pass_at_1: gate_rate,
        graded_pass_at_1: graded_rate,
        gate_threshold: gate_threshold,
        graded_threshold: graded_threshold,
        reason: reasons.empty? ? nil : reasons.join("; ")
      )
    end

    def self.infer_role(scenario_id)
      case scenario_id.to_s
      when /scoped/i then "scoped_coder"
      when /pii/i then "sanitizer"
      when /ocr|extract/i then "extractor"
      when /triage|email/i then "triager"
      else "coder"
      end
    end

    def self.pass_at_1_rate(tasks, kind:)
      selected = tasks.select { |t| t["kind"].to_s == kind }
      return 1.0 if selected.empty?

      passes = selected.count { |t| truthy_pass_at_1?(t["pass_at_1"]) }
      passes.to_f / selected.size
    end

    def self.truthy_pass_at_1?(value)
      value == true || value == 1 || value == 1.0
    end

    def self.format_rate(value)
      format("%.2f", value.to_f)
    end
    private_class_method :format_rate, :truthy_pass_at_1?
  end
end
