# frozen_string_literal: true

require "json"

module Alpha
  # Builds a cross-run capability map table for campaign docs.
  module CapabilityMap
    module_function

    def build(run_ids, results_dir: Alpha.config.results_dir)
      rows = []
      Array(run_ids).each do |run_id|
        path = File.join(results_dir, "runs", run_id.to_s, "summary.json")
        next unless File.file?(path)

        summary = JSON.parse(File.read(path))
        scenario = begin
          Scenario.load(summary["scenario"])
        rescue ArgumentError
          nil
        end
        verdict = Qualifier.evaluate(summary, scenario: scenario)
        agg = summary["aggregate"] || {}
        rows << {
          "run_id" => summary["run_id"] || run_id,
          "model_id" => summary["model_id"],
          "role" => verdict.role,
          "scenario" => summary["scenario"],
          "prompt_preset" => summary["prompt_preset"],
          "max_rung" => verdict.max_rung || agg["highest_rung_passed"],
          "ceiling_rung" => agg["ceiling_rung"],
          "credit_mean" => verdict.credit_mean || agg["credit_mean"],
          "pass_at_1" => verdict.graded_pass_at_1,
          "qualified" => verdict.qualified,
          "top_failures" => top_failures(verdict.failure_class_histogram || agg["failure_class_histogram"]),
          "ship_skills" => verdict.ship_skills
        }
      end
      rows
    end

    def render_markdown(rows)
      lines = []
      lines << "# Capability map"
      lines << ""
      lines << "| Model | Role | Max rung | Ceiling | Credit | Pass@1 | Qualified | Top failures |"
      lines << "|---|---|---|---|---|---|---|---|"
      rows.each do |r|
        lines << "| `#{r["model_id"]}` | `#{r["role"]}` | #{r["max_rung"] || "—"} | #{r["ceiling_rung"] || "—"} | #{r["credit_mean"]} | #{format("%.2f", r["pass_at_1"].to_f)} | #{r["qualified"] ? "yes" : "no"} | #{r["top_failures"]} |"
      end
      lines << ""
      lines.join("\n")
    end

    def top_failures(histogram)
      hist = histogram || {}
      hist.reject { |k, _| k.to_s == "none" }
          .sort_by { |_, v| -v.to_i }
          .first(3)
          .map { |k, v| "#{k}:#{v}" }
          .join(", ")
    end
    private_class_method :top_failures
  end
end
