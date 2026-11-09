# frozen_string_literal: true

require "fileutils"
require "json"

module Alpha
  # Aggregates MetricRecords into alpha.report.v2 JSON under results/<run_id>/summary.json
  # and permanent Markdown report under reports/<run_id>.md.
  class Report
    def self.results_dir
      Alpha.config.results_dir
    end

    def self.reports_dir
      Alpha.config.reports_dir
    end

    def self.build(run_id, scenario:, model_id:, prompt_preset:, inference_target:, task_records:,
                   suite_complete: true, dry_run: false)
      scored = task_records.select { |t| t[:scored] != false && t[:invalid] != true }
      invalid = task_records.select { |t| t[:invalid] == true }
      tasks_total = scored.size
      tasks_passed = scored.count { |t| truthy_pass_at_1?(t[:pass_at_1]) }
      pass_at_1 = tasks_total.positive? ? (tasks_passed.to_f / tasks_total).round(2) : 0.0

      tool_calls_total = task_records.sum { |t| t[:tool_calls] || 0 }
      tool_calls_mean = task_records.size.positive? ? (tool_calls_total.to_f / task_records.size).round(1) : 0.0
      wall_ms_total = task_records.sum { |t| t[:wall_ms] || 0 }
      prompt_tokens_total = task_records.sum { |t| t[:prompt_tokens] || 0 }
      completion_tokens_total = task_records.sum { |t| t[:completion_tokens] || 0 }
      budgeted = task_records.select { |t| t[:latency_budget_ms] }
      within_budget_count = budgeted.count { |t| t[:within_budget] == true }

      credits = scored.map { |t| t[:credit] }.compact
      credit_mean = credits.empty? ? 0.0 : (credits.sum.to_f / credits.size).round(2)

      histogram = Hash.new(0)
      task_records.each do |t|
        fc = (t[:failure_class] || "unknown").to_s
        histogram[fc] += 1
      end

      passed_rungs = scored.select { |t| truthy_pass_at_1?(t[:pass_at_1]) && t[:rung] }.map { |t| t[:rung] }
      highest = passed_rungs.empty? ? nil : Alpha::Rung.max(*passed_rungs)

      status = build_status(
        task_records: task_records,
        scored: scored,
        invalid: invalid,
        suite_complete: suite_complete,
        dry_run: dry_run,
        pass_at_1: pass_at_1,
        scenario: scenario,
        prompt_preset: prompt_preset
      )

      summary_payload = {
        "schema" => "alpha.report.v2",
        "run_id" => run_id,
        "scenario" => scenario.is_a?(String) ? scenario : scenario.id,
        "model_id" => model_id,
        "prompt_preset" => prompt_preset,
        "suite_complete" => suite_complete,
        "dry_run" => dry_run,
        "qualification_eligible" => status["qualification_eligible"],
        "status" => status,
        "inference" => {
          "base_url" => inference_target.respond_to?(:base_url) ? inference_target.base_url : inference_target.to_s,
          "preset" => inference_target.respond_to?(:engine_preset) ? inference_target.engine_preset : nil
        },
        "aggregate" => {
          "pass_at_1" => pass_at_1,
          "first_attempt_success" => pass_at_1,
          "tasks_passed" => tasks_passed,
          "tasks_total" => tasks_total,
          "pass_at_1_numerator" => tasks_passed,
          "pass_at_1_denominator" => tasks_total,
          "scored_tasks_total" => scored.size,
          "scored_tasks_passed" => tasks_passed,
          "invalid_trials" => invalid.size,
          "tool_calls_mean" => tool_calls_mean,
          "wall_ms_total" => wall_ms_total,
          "prompt_tokens_total" => prompt_tokens_total,
          "completion_tokens_total" => completion_tokens_total,
          "credit_mean" => credit_mean,
          "failure_class_histogram" => histogram,
          "highest_rung_passed" => highest,
          "ceiling_rung" => highest,
          "latency_budgeted_tasks" => budgeted.size,
          "latency_within_budget" => within_budget_count,
          "workflow_fit" => workflow_fit_summary(task_records)
        },
        "tasks" => task_records.map { |t| task_payload(t) }
      }

      run_results_dir = File.join(results_dir, "runs", run_id)
      FileUtils.mkdir_p(run_results_dir)
      summary_path = File.join(run_results_dir, "summary.json")
      File.write(summary_path, JSON.pretty_generate(summary_payload))

      FileUtils.mkdir_p(reports_dir)
      report_path = File.join(reports_dir, "#{run_id}.md")
      File.write(report_path, render_markdown(summary_payload))

      {
        summary_path: summary_path,
        report_path: report_path,
        payload: summary_payload
      }
    end

    def self.task_payload(t)
      {
        "name" => t[:task_name],
        "kind" => t[:kind],
        "skill" => t[:skill],
        "rung" => t[:rung],
        "scaffold" => t[:scaffold],
        "trial" => t[:trial],
        "trial_id" => t[:trial_id],
        "pass" => t[:pass],
        "pass_at_1" => t[:pass_at_1],
        "credit" => t[:credit],
        "scored" => t.fetch(:scored, true),
        "invalid" => t.fetch(:invalid, false),
        "invalid_reason" => t[:invalid_reason],
        "failure_class" => t[:failure_class],
        "thinking_level" => t[:thinking_level],
        "tool_calls" => t[:tool_calls] || 0,
        "prompt_tokens" => t[:prompt_tokens] || 0,
        "completion_tokens" => t[:completion_tokens] || 0,
        "wall_ms" => t[:wall_ms] || 0,
        "latency_budget_ms" => t[:latency_budget_ms],
        "workflow_tier" => t[:workflow_tier],
        "within_budget" => t[:within_budget],
        "graders" => t[:graders] || []
      }
    end
    private_class_method :task_payload

    def self.build_status(task_records:, scored:, invalid:, suite_complete:, dry_run:, pass_at_1:,
                          scenario:, prompt_preset:)
      execution_health = if dry_run
        "planning_only"
      elsif invalid.any?
        "infrastructure_invalid"
      else
        "ok"
      end

      gate_tasks = scored.select { |t| t[:kind].to_s == "gate" }
      gate_status = if dry_run
        "not_scored"
      elsif gate_tasks.empty?
        "not_applicable"
      elsif !suite_complete
        "incomplete"
      elsif gate_tasks.all? { |t| truthy_pass_at_1?(t[:pass_at_1]) }
        "passed"
      else
        "failed"
      end

      graded_tasks = scored.select { |t| t[:kind].to_s == "graded" }
      threshold = if scenario.respond_to?(:qualification)
        scenario.qualification[:graded_pass_at_1].to_f
      else
        0.70
      end
      graded_rate = if graded_tasks.empty?
        1.0
      else
        graded_tasks.count { |t| truthy_pass_at_1?(t[:pass_at_1]) }.to_f / graded_tasks.size
      end

      benchmark_verdict = if dry_run
        "not_scored"
      elsif !suite_complete || task_records.empty?
        "incomplete"
      elsif invalid.any?
        "not_evaluated"
      elsif gate_status == "failed" || graded_rate < threshold
        "fail"
      else
        "pass"
      end

      statistical_sufficiency = if dry_run || !suite_complete || invalid.any? || scored.empty?
        "not_evaluated"
      else
        # Phase 1 reports first-attempt evidence only; multi-seed sufficiency is Phase 7.
        "single_trial_evidence"
      end

      qualification_eligible = !dry_run && suite_complete && invalid.empty? && scored.any? &&
                               gate_status != "failed" && gate_status != "incomplete"

      {
        "execution_health" => execution_health,
        "gate_status" => gate_status,
        "benchmark_verdict" => benchmark_verdict,
        "statistical_sufficiency" => statistical_sufficiency,
        "qualification_eligible" => qualification_eligible,
        # Routing authority is never granted from Alpha local/dev runs.
        "routing_authority" => "none",
        "prompt_preset" => prompt_preset.to_s,
        "first_attempt_success" => pass_at_1
      }
    end
    private_class_method :build_status

    def self.render_markdown(data)
      agg = data["aggregate"]
      status = data["status"] || {}
      lines = []
      lines << "# Alpha Evaluation Report: #{data["run_id"]}"
      lines << ""
      lines << "## Capability summary"
      lines << ""
      lines << "| Metric | Value |"
      lines << "|---|---|"
      lines << "| **Scenario** | `#{data["scenario"]}` |"
      lines << "| **Model** | `#{data["model_id"]}` |"
      lines << "| **Evaluation mode** | `#{data["prompt_preset"]}` |"
      lines << "| **First-attempt success** | **#{agg["pass_at_1"]}** " \
               "(#{agg["pass_at_1_numerator"] || agg["tasks_passed"]}/#{agg["pass_at_1_denominator"] || agg["tasks_total"]}) |"
      lines << "| **Credit mean** | #{agg["credit_mean"]} |"
      lines << "| **Highest rung passed** | #{agg["highest_rung_passed"] || "—"} |"
      lines << "| **Invalid trials** | #{agg["invalid_trials"]} |"
      lines << "| **Suite complete** | #{data["suite_complete"] != false} |"
      lines << "| **Dry run** | #{data["dry_run"] == true} |"
      lines << "| **Execution health** | #{status["execution_health"] || "—"} |"
      lines << "| **Gate status** | #{status["gate_status"] || "—"} |"
      lines << "| **Benchmark verdict** | #{status["benchmark_verdict"] || "—"} |"
      lines << "| **Statistical sufficiency** | #{status["statistical_sufficiency"] || "—"} |"
      lines << "| **Meets delegation policy** | #{data["qualification_eligible"] ? "eligible evidence" : "no"} |"
      lines << "| **Routing authority** | #{status["routing_authority"] || "none"} |"
      lines << "| **Mean Tool Calls** | #{agg["tool_calls_mean"]} |"
      lines << "| **Total Wall Time** | #{(agg["wall_ms_total"].to_i / 1000.0).round(1)}s |"
      lines << "| **Total Tokens** | #{agg["prompt_tokens_total"]} prompt / #{agg["completion_tokens_total"]} completion |"
      if agg["latency_budgeted_tasks"].to_i.positive?
        lines << "| **Latency within budget** | #{agg["latency_within_budget"]}/#{agg["latency_budgeted_tasks"]} |"
        fit = agg["workflow_fit"] || {}
        lines << "| **Workflow fit** | interactive=#{fit["interactive"] || 0}, assistive=#{fit["assistive"] || 0}, batch=#{fit["batch"] || 0}, unusable=#{fit["unusable"] || 0} |"
      end
      lines << ""
      hist = agg["failure_class_histogram"] || {}
      if hist.any?
        lines << "### Failure-class histogram"
        lines << ""
        lines << "| Class | Count |"
        lines << "|---|---|"
        hist.sort_by { |k, _| k.to_s }.each do |klass, count|
          lines << "| `#{klass}` | #{count} |"
        end
        lines << ""
      end
      lines << "## Task Breakdown"
      lines << ""
      lines << "| Task | Kind | Rung | First-attempt | Credit | Failure | Scored | Wall (s) | Verdict |"
      lines << "|---|---|---|---|---|---|---|---|---|"

      Array(data["tasks"]).each do |t|
        verdict = if t["invalid"]
          "⚠ Not evaluated: infrastructure failure"
        elsif t["pass_at_1"]
          "✅ PASS"
        else
          "❌ FAIL"
        end
        wall_s = (t["wall_ms"].to_i / 1000.0).round(1)
        credit = t["credit"].nil? ? "—" : format("%.2f", t["credit"].to_f)
        first = t["pass_at_1"] ? "1.0" : "0.0"
        lines << "| `#{t["name"]}` | #{t["kind"]} | #{t["rung"] || "—"} | #{first} | #{credit} | #{t["failure_class"] || "—"} | #{t["scored"] == false ? "no" : "yes"} | #{wall_s} | #{verdict} |"
      end

      if Array(data["tasks"]).empty? && data["dry_run"]
        lines << ""
        lines << "_Planning-only dry run: no scored trial rows._"
      end

      lines << ""
      lines << "---"
      lines << "*Generated by Project Alpha (`alpha.report.v2`)*"
      lines << ""
      lines.join("\n")
    end

    def self.workflow_fit_summary(task_records)
      counts = { "interactive" => 0, "assistive" => 0, "batch" => 0, "unusable" => 0 }
      task_records.each do |t|
        budget = t[:latency_budget_ms]
        next unless budget

        wall = t[:wall_ms].to_i
        declared = t[:workflow_tier].to_s
        fit = if wall > budget
          "unusable"
        elsif %w[interactive assistive batch].include?(declared)
          declared
        elsif wall <= 3_000
          "interactive"
        elsif wall <= 15_000
          "assistive"
        elsif wall <= 60_000
          "batch"
        else
          "unusable"
        end
        counts[fit] += 1
      end
      counts
    end
    private_class_method :workflow_fit_summary

    def self.truthy_pass_at_1?(value)
      value == true || value == 1 || value == 1.0
    end
    private_class_method :truthy_pass_at_1?
  end
end
