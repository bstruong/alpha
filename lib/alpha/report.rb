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
                   suite_complete: true, dry_run: false, provenance: nil, generation_params: nil)
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
      # Deterministic key order for byte-stable report regeneration.
      histogram = histogram.sort_by { |k, _| k.to_s }.to_h

      passed_rungs = scored.select { |t| truthy_pass_at_1?(t[:pass_at_1]) && t[:rung] }.map { |t| t[:rung] }
      highest = passed_rungs.empty? ? nil : Alpha::Rung.max(*passed_rungs)

      protocol = StatisticalProtocol.load
      coverage, reliability = coverage_and_reliability(task_records)
      status = build_status(
        task_records: task_records,
        scored: scored,
        invalid: invalid,
        suite_complete: suite_complete,
        dry_run: dry_run,
        pass_at_1: pass_at_1,
        scenario: scenario,
        prompt_preset: prompt_preset,
        protocol: protocol
      )

      provenance_payload = provenance || Provenance.collect(
        run_id: run_id,
        scenario: scenario.is_a?(String) ? nil : scenario,
        inference_target: inference_target.respond_to?(:model_id) ? inference_target : nil,
        generation_params: generation_params,
        seed: scenario.respond_to?(:seed) ? scenario.seed : nil
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
        "promotable" => provenance_payload["promotable"] == true && status["qualification_eligible"],
        "run_manifest_uri" => "results/runs/#{run_id}/#{RunManifest::FILENAME}",
        "status" => status,
        "statistical_protocol" => protocol.payload_fragment(
          valid_trials: tasks_total,
          successes: tasks_passed
        ),
        "coverage" => coverage,
        "reliability" => reliability,
        "inference" => {
          "base_url" => if inference_target.respond_to?(:base_url)
                          Provenance.sanitize_url(inference_target.base_url)
                        else
                          Provenance.sanitize_url(inference_target.to_s)
                        end,
          "preset" => inference_target.respond_to?(:engine_preset) ? inference_target.engine_preset : nil
        },
        "provenance" => provenance_payload,
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
      File.write(summary_path, JSON.pretty_generate(summary_payload) + "\n")

      FileUtils.mkdir_p(reports_dir)
      report_path = File.join(reports_dir, "#{run_id}.md")
      File.write(report_path, render_markdown(summary_payload))

      {
        summary_path: summary_path,
        report_path: report_path,
        payload: summary_payload
      }
    end

    # Regenerate Markdown byte-for-byte from a retained summary bundle (plus optional manifest).
    def self.render_from_bundle(summary_payload, run_manifest: nil)
      data = summary_payload.dup
      if run_manifest
        data = data.merge(
          "run_manifest" => {
            "schema" => run_manifest["schema"],
            "status" => run_manifest["status"],
            "terminal_status" => run_manifest["terminal_status"],
            "artifact_hashes" => run_manifest["artifact_hashes"]
          }
        )
      end
      render_markdown(data)
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
        "seed" => t[:seed],
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
        "evidence_uri" => t[:evidence_uri] || evidence_uri_for(t),
        "graders" => t[:graders] || []
      }
    end
    private_class_method :task_payload

    def self.evidence_uri_for(t)
      run_id = t[:run_id]
      task = t[:task_name]
      trial = t[:trial] || 1
      return nil unless run_id && task

      "results/runs/#{run_id}/#{task}/trial-#{trial}/result.json"
    end
    private_class_method :evidence_uri_for

    def self.build_status(task_records:, scored:, invalid:, suite_complete:, dry_run:, pass_at_1:,
                          scenario:, prompt_preset:, protocol: nil)
      protocol ||= StatisticalProtocol.load
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
        protocol.statistical_sufficiency(valid_trial_count: scored.size)
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
      agg = data["aggregate"] || {}
      status = data["status"] || {}
      provenance = data["provenance"] || {}
      lines = []
      lines << "# Alpha Evaluation Report: #{data["run_id"]}"
      lines << ""
      lines.concat(capability_summary_lines(data, agg, status, provenance))
      lines << ""
      lines.concat(evidence_boundary_lines(data, provenance))
      lines << ""
      lines.concat(supporting_evidence_lines(data, agg, status, provenance))
      lines << ""
      lines << "---"
      lines << "*Generated by Project Alpha (`alpha.report.v2`) from retained run bundle*"
      lines << ""
      lines.join("\n")
    end

    def self.capability_summary_lines(data, agg, status, provenance)
      can_do, cannot, not_eval = partition_outcome_tasks(data)
      protocol = data["statistical_protocol"] || {}
      model_identity = [
        data["model_id"],
        provenance.dig("model", "quantization"),
        provenance.dig("model", "model_sha256")
      ].compact.join(" / ")
      protocol_label = [
        protocol["protocol_id"],
        protocol["protocol_version"]
      ].compact.join("@")

      lines = []
      lines << "Model: `#{model_identity.empty? ? data["model_id"] : model_identity}`"
      scope = "`#{data["scenario"]}` / `#{data["prompt_preset"]}`"
      scope = "#{scope} / protocol `#{protocol_label}`" unless protocol_label.empty?
      lines << "Evaluated for: #{scope}"
      lines << ""
      lines << "## Can do"
      if can_do.empty?
        lines << "- _(none)_"
      else
        can_do.each { |row| lines << "- #{row}" }
      end
      lines << ""
      lines << "## Cannot reliably do"
      if cannot.empty?
        lines << "- _(none)_"
      else
        cannot.each { |row| lines << "- #{row}" }
      end
      lines << ""
      lines << "## Not evaluated"
      if not_eval.empty?
        lines << "- _(none)_"
      else
        not_eval.each { |row| lines << "- #{row}" }
      end
      lines << ""
      lines << "## Delegation decision"
      lines << "- Unattended: none (protocol unattended_enabled=false; Alpha never grants routing authority)"
      lines << "- Review required: all scored tasks pending fresh held-out evidence that meets policy"
      lines << "- Do not delegate: tasks with observed critical semantic or safety failures"
      lines
    end
    private_class_method :capability_summary_lines

    def self.partition_outcome_tasks(data)
      can_do = []
      cannot = []
      not_eval = []
      by_name = Hash.new { |h, k| h[k] = [] }
      Array(data["tasks"]).each { |t| by_name[t["name"].to_s] << t }

      by_name.keys.sort.each do |name|
        rows = by_name[name]
        label = "`#{name}`"
        invalid_rows = rows.select { |t| t["invalid"] || t["scored"] == false }
        scored_rows = rows - invalid_rows
        if scored_rows.empty?
          reason = invalid_rows.map { |t| t["invalid_reason"] || "not scored" }.uniq.join("; ")
          not_eval << "#{label}: #{reason}"
          next
        end

        passed = scored_rows.count { |t| truthy_pass_at_1?(t["pass_at_1"]) }
        total = scored_rows.size
        if passed == total
          can_do << "#{label}: #{passed}/#{total} passed"
        else
          failures = scored_rows.reject { |t| truthy_pass_at_1?(t["pass_at_1"]) }
                                .map { |t| t["failure_class"] || "unknown" }
                                .uniq
                                .join(", ")
          cannot << "#{label}: #{passed}/#{total} passed; Observed failures: #{failures}"
        end
      end
      [can_do, cannot, not_eval]
    end
    private_class_method :partition_outcome_tasks

    def self.evidence_boundary_lines(data, provenance)
      agg = data["aggregate"] || {}
      status = data["status"] || {}
      protocol = data["statistical_protocol"] || {}
      interval = protocol.dig("uncertainty", "interval")
      uncertainty = if interval
        method = protocol.dig("uncertainty", "method") || "wilson_score_interval"
        level = protocol.dig("uncertainty", "confidence_level") || 0.95
        "#{method} #{level} [#{interval["lower"]}, #{interval["upper"]}] on observed " \
          "#{agg["pass_at_1_numerator"] || agg["tasks_passed"]}/#{agg["pass_at_1_denominator"] || agg["tasks_total"]}; " \
          "never interpret a 1.0 point estimate as certainty"
      else
        "not evaluated (no valid trials)"
      end

      lines = []
      lines << "## Evidence limits"
      lines << ""
      lines << "- Valid trials: #{agg["pass_at_1_denominator"] || agg["tasks_total"] || 0}; " \
               "invalid trials: #{agg["invalid_trials"] || 0}"
      lines << "- Uncertainty: #{uncertainty}"
      lines << "- Runtime identity: runner=#{provenance.dig("runner", "image_digest") || "—"}, " \
               "jarvis=#{provenance.dig("jarvis", "image_digest") || "—"}"
      lines << "- Evidence expires when: model/runtime/source/fixture/protocol hashes change, or qualification TTL elapses"
      lines << "- Coverage vs reliability: coverage answers which tasks were attempted; " \
               "reliability is repeated-trial First-attempt success with exact N/D (see Supporting evidence)"
      lines << "- Observed success only — never claim absolute certainty " \
               "(statistical_sufficiency=#{status["statistical_sufficiency"] || "not_evaluated"})"
      lines
    end
    private_class_method :evidence_boundary_lines

    def self.supporting_evidence_lines(data, agg, status, provenance)
      lines = []
      lines << "## Supporting evidence"
      lines << ""
      lines << "### Task coverage"
      Array(data.dig("coverage", "tasks")).each { |row| lines << "- #{row}" }
      lines << "- _(none)_" if Array(data.dig("coverage", "tasks")).empty?
      lines << ""
      lines << "### Repeated-trial reliability"
      Array(data.dig("reliability", "per_task")).each { |row| lines << "- #{row}" }
      lines << "- _(none)_" if Array(data.dig("reliability", "per_task")).empty?
      lines << ""
      lines << "### Metrics"
      lines << ""
      lines << "| Metric | Value |"
      lines << "|---|---|"
      lines << "| Scenario | `#{data["scenario"]}` |"
      lines << "| Model | `#{data["model_id"]}` |"
      lines << "| Evaluation mode | `#{data["prompt_preset"]}` |"
      lines << "| First-attempt success | #{agg["pass_at_1"]} " \
               "(#{agg["pass_at_1_numerator"] || agg["tasks_passed"]}/#{agg["pass_at_1_denominator"] || agg["tasks_total"]}) |"
      lines << "| Credit mean | #{agg["credit_mean"]} |"
      lines << "| Highest rung passed | #{agg["highest_rung_passed"] || "—"} |"
      lines << "| Suite complete | #{data["suite_complete"] != false} |"
      lines << "| Dry run | #{data["dry_run"] == true} |"
      lines << "| Execution health | #{status["execution_health"] || "—"} |"
      lines << "| Gate status | #{status["gate_status"] || "—"} |"
      lines << "| Benchmark verdict | #{status["benchmark_verdict"] || "—"} |"
      lines << "| Statistical sufficiency | #{status["statistical_sufficiency"] || "—"} |"
      lines << "| Meets delegation policy | #{data["qualification_eligible"] ? "eligible evidence" : "no"} |"
      lines << "| Promotable | #{data["promotable"] ? "yes" : "no"} |"
      lines << "| Routing authority | #{status["routing_authority"] || "none"} |"
      lines << "| Mean tool calls | #{agg["tool_calls_mean"]} |"
      lines << "| Total wall time | #{(agg["wall_ms_total"].to_i / 1000.0).round(1)}s |"
      lines << "| Total tokens | #{agg["prompt_tokens_total"]} prompt / #{agg["completion_tokens_total"]} completion |"
      if agg["latency_budgeted_tasks"].to_i.positive?
        lines << "| Latency within budget | #{agg["latency_within_budget"]}/#{agg["latency_budgeted_tasks"]} |"
        fit = agg["workflow_fit"] || {}
        lines << "| Workflow fit | interactive=#{fit["interactive"] || 0}, assistive=#{fit["assistive"] || 0}, batch=#{fit["batch"] || 0}, unusable=#{fit["unusable"] || 0} |"
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

      lines << "### Task breakdown"
      lines << ""
      lines << "| Task | Kind | Rung | First-attempt | Credit | Failure | Scored | Wall (s) | Evidence | Verdict |"
      lines << "|---|---|---|---|---|---|---|---|---|---|"
      Array(data["tasks"]).each do |t|
        verdict = if t["invalid"]
          "Not evaluated: infrastructure failure"
        elsif t["pass_at_1"]
          "PASS"
        else
          "FAIL"
        end
        wall_s = (t["wall_ms"].to_i / 1000.0).round(1)
        credit = t["credit"].nil? ? "—" : format("%.2f", t["credit"].to_f)
        first = t["pass_at_1"] ? "1.0" : "0.0"
        evidence = t["evidence_uri"] || t["trial_id"] || "—"
        lines << "| `#{t["name"]}` | #{t["kind"]} | #{t["rung"] || "—"} | #{first} | #{credit} | #{t["failure_class"] || "—"} | #{t["scored"] == false ? "no" : "yes"} | #{wall_s} | `#{evidence}` | #{verdict} |"
      end
      if Array(data["tasks"]).empty? && data["dry_run"]
        lines << ""
        lines << "_Planning-only dry run: no scored trial rows._"
      end
      lines << ""

      repos = provenance["repositories"] || {}
      lines << "### Provenance, Lease, and Kubernetes"
      lines << "- Commits: alpha=`#{repos.dig("alpha", "commit") || "—"}` " \
               "(dirty=#{repos.dig("alpha", "dirty").inspect}), " \
               "alpha-lab=`#{repos.dig("alpha_lab", "commit") || "—"}`, " \
               "homelab=`#{repos.dig("homelab_k3s", "commit") || "—"}`"
      lines << "- Content hashes: scenario=`#{provenance.dig("content", "scenario_hash") || "—"}` " \
               "fixture_set=`#{provenance.dig("content", "fixture_set_hash") || "—"}`"
      lines << "- Lease: holder=`#{provenance.dig("lease", "holder") || "—"}` " \
               "run_id=`#{provenance.dig("lease", "run_id") || "—"}`"
      job = provenance.dig("graded_host", "job_name") || provenance.dig("graded_host", "watchtower_job") || "—"
      lines << "- Kubernetes Job: `#{job}` (graded suites are Watchtower Job-only)"
      lines << "- Machine-readable evidence index: " \
               "`#{data["run_manifest_uri"] || "results/runs/#{data["run_id"]}/run_manifest.json"}`"
      lines << "- Promotable blockers: #{Array(provenance["promotable_blockers"]).empty? ? "none" : provenance["promotable_blockers"].join("; ")}"
      if (manifest = data["run_manifest"])
        lines << "- Terminal status: #{manifest["terminal_status"] || "—"}"
        lines << "- Artifact hashes retained: #{(manifest["artifact_hashes"] || {}).size}"
      end
      lines
    end
    private_class_method :supporting_evidence_lines

    def self.coverage_and_reliability(task_records)
      by_name = Hash.new { |h, k| h[k] = [] }
      task_records.each { |t| by_name[t[:task_name].to_s] << t }

      coverage_tasks = []
      reliability_rows = []
      by_name.keys.sort.each do |name|
        rows = by_name[name]
        scored = rows.reject { |t| t[:invalid] == true || t[:scored] == false }
        if scored.empty?
          coverage_tasks << "`#{name}`: not evaluated"
          next
        end
        coverage_tasks << "`#{name}`: attempted (#{scored.size} scored trial(s))"
        passed = scored.count { |t| truthy_pass_at_1?(t[:pass_at_1]) }
        total = scored.size
        interval = StatisticalProtocol.wilson_interval(passed, total)
        band = if interval
          format("Wilson 95%% [%.3f, %.3f]", interval[0], interval[1])
        else
          "n/a"
        end
        seeds = scored.map { |t| t[:seed] }.compact.uniq.sort
        reliability_rows << "`#{name}`: #{passed}/#{total} first-attempt; #{band}; seeds=#{seeds.empty? ? "undeclared" : seeds.inspect}"
      end

      skills = task_records.map { |t| t[:skill] }.compact.uniq.sort
      [
        {
          "tasks" => coverage_tasks,
          "skills_attempted" => skills,
          "tasks_not_evaluated" => coverage_tasks.select { |row| row.include?("not evaluated") }
        },
        {
          "per_task" => reliability_rows,
          "aggregate" => {
            "note" => "Repeated-trial reliability is distinct from single-pass task coverage"
          }
        }
      ]
    end
    private_class_method :coverage_and_reliability

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
