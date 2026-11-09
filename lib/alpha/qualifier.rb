# frozen_string_literal: true

module Alpha
  # Deterministic first-attempt qualification against a scenario's configured thresholds (v2).
  # Separates score thresholds from routing authority (always none here).
  class Qualifier
    Result = Data.define(
      :qualified,
      :role,
      :scenario_id,
      :gate_pass_at_1,
      :graded_pass_at_1,
      :gate_threshold,
      :graded_threshold,
      :max_rung,
      :credit_mean,
      :failure_class_histogram,
      :ship_skills,
      :execution_health,
      :gate_status,
      :benchmark_verdict,
      :statistical_sufficiency,
      :qualification_eligible,
      :routing_authority,
      :reason
    )

    def self.evaluate(summary, scenario: nil, role: nil)
      scenario_id = summary["scenario"].to_s
      profile_name = (summary["prompt_preset"] || summary.dig("status", "prompt_preset") || "shipping").to_s

      scenario ||= begin
        Scenario.load(scenario_id, profile: profile_name)
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
      skill_threshold = thresholds[:skill_pass_at_1]
      max_shipping_rung = scenario&.profile&.max_rung

      all_tasks = Array(summary["tasks"])
      reasons = []

      # Structural eligibility — fail closed before scoring.
      if summary["dry_run"] == true || summary.dig("status", "execution_health") == "planning_only"
        reasons << "dry-run summaries are not qualification-eligible"
      end
      if summary.key?("suite_complete") && summary["suite_complete"] == false
        reasons << "partial suite (--task / suite_complete=false) cannot qualify"
      end
      if summary.key?("qualification_eligible") && summary["qualification_eligible"] == false
        reasons << "summary marks qualification_eligible=false"
      end

      if scenario.nil?
        reasons << "scenario #{scenario_id.inspect} could not be loaded for profile #{profile_name.inspect}"
      else
        expected_profile = scenario.profile.name.to_s
        if expected_profile != profile_name
          reasons << "profile mismatch: summary=#{profile_name.inspect} scenario=#{expected_profile.inspect}"
        end
        if scenario.id.to_s != scenario_id
          reasons << "scenario id mismatch: summary=#{scenario_id.inspect} loaded=#{scenario.id.inspect}"
        end

        expected_names = scenario.tasks.map(&:name).sort
        actual_names = all_tasks.map { |t| t["name"].to_s }.uniq.sort
        unless expected_names == actual_names
          missing = expected_names - actual_names
          extra = actual_names - expected_names
          parts = []
          parts << "missing=#{missing.join(",")}" if missing.any?
          parts << "extra=#{extra.join(",")}" if extra.any?
          reasons << "incomplete expected task set (#{parts.join("; ")})"
        end
      end

      name_trial_keys = all_tasks.map { |t| [ t["name"].to_s, t["trial"] || t["trial_id"] || 1 ] }
      if name_trial_keys.size != name_trial_keys.uniq.size
        reasons << "duplicate task/trial ids"
      end
      trial_ids = all_tasks.map { |t| t["trial_id"] }.compact
      if trial_ids.size != trial_ids.uniq.size
        reasons << "duplicate trial_id values"
      end

      infra_invalid = all_tasks.select { |t| t["invalid"] == true || t["failure_class"].to_s == "infra" }
      if infra_invalid.any?
        reasons << "infrastructure-invalid rows present (#{infra_invalid.size})"
      end
      if all_tasks.any? { |t| t["dry_run"] == true }
        reasons << "dry-run rows present"
      end

      tasks = all_tasks.select { |t| scored_task?(t) }
      if max_shipping_rung
        tasks = tasks.select do |t|
          t["rung"].nil? || Alpha::Rung.<=(t["rung"], max_shipping_rung)
        end
      end

      scored_graded = tasks.count { |t| t["kind"].to_s == "graded" }
      scored_gate = tasks.count { |t| t["kind"].to_s == "gate" }
      empty_scored = scored_graded.zero? && scored_gate.zero?

      gate_rate = empty_scored ? 0.0 : pass_at_1_rate(tasks, kind: "gate")
      graded_rate = empty_scored ? 0.0 : pass_at_1_rate(tasks, kind: "graded")
      max_rung = highest_passed_rung(tasks)
      credit_mean = mean_credit(tasks)
      histogram = failure_histogram(all_tasks)
      skills = ship_skills(tasks)

      if empty_scored
        reasons << "no scored tasks (#{infra_invalid.size} infra/invalid of #{all_tasks.size})"
      end
      if !empty_scored && scored_gate.positive? && gate_rate < gate_threshold
        reasons << "gate Pass@1 #{format_rate(gate_rate)} < #{format_rate(gate_threshold)}"
      end
      if !empty_scored && scored_graded.positive? && graded_rate < graded_threshold
        reasons << "graded Pass@1 #{format_rate(graded_rate)} < #{format_rate(graded_threshold)}"
      end

      # Required gate outcomes: scenario gates must appear when the suite declares them.
      if scenario && scenario.tasks.any?(&:gate?) && scored_gate.zero? && !empty_scored
        reasons << "required gate outcomes missing"
      end

      if scenario && !empty_scored
        expected_skills = scenario.tasks.map { |t| t.skill.to_s.empty? ? "general" : t.skill.to_s }.uniq.sort
        actual_skills = skills.map { |s| s["skill"] }.sort
        missing_skills = expected_skills - actual_skills
        reasons << "required per-skill outcomes missing: #{missing_skills.join(",")}" if missing_skills.any?
      end
      if skill_threshold
        floor = skill_threshold.to_f
        skills.each do |row|
          if row["pass_at_1"].to_f < floor
            reasons << "skill #{row["skill"]} Pass@1 #{format_rate(row["pass_at_1"])} < #{format_rate(floor)}"
          end
        end
      end

      min_rung = thresholds[:min_rung]
      if min_rung && (max_rung.nil? || Alpha::Rung.compare(max_rung, min_rung).negative?)
        reasons << "max_rung #{max_rung || "none"} < min_rung #{Alpha::Rung.normalize(min_rung)}"
      end

      if scenario&.qualification&.fetch(:require_baselines, false)
        baseline_reason = missing_baseline_reason(scenario.id)
        reasons << baseline_reason if baseline_reason
      end

      status = summary["status"].is_a?(Hash) ? summary["status"] : {}
      execution_health = status["execution_health"] || (infra_invalid.any? ? "infrastructure_invalid" : "ok")
      gate_status = status["gate_status"] || (gate_rate >= gate_threshold ? "passed" : "failed")
      benchmark_verdict = status["benchmark_verdict"] || (reasons.empty? ? "pass" : "fail")
      statistical_sufficiency = status["statistical_sufficiency"] || "not_evaluated"
      qualification_eligible = reasons.empty?
      # Alpha never grants routing authority; alpha-lab Phase 7 owns Unattended decisions.
      routing_authority = "none"

      Result.new(
        qualified: qualification_eligible,
        role: target_role,
        scenario_id: scenario_id,
        gate_pass_at_1: gate_rate,
        graded_pass_at_1: graded_rate,
        gate_threshold: gate_threshold,
        graded_threshold: graded_threshold,
        max_rung: max_rung,
        credit_mean: credit_mean,
        failure_class_histogram: histogram,
        ship_skills: skills,
        execution_health: execution_health,
        gate_status: gate_status,
        benchmark_verdict: benchmark_verdict,
        statistical_sufficiency: statistical_sufficiency,
        qualification_eligible: qualification_eligible,
        routing_authority: routing_authority,
        reason: reasons.empty? ? nil : reasons.uniq.join("; ")
      )
    end

    def self.infer_role(scenario_id)
      case scenario_id.to_s
      when /scoped/i then "scoped_coder"
      when /vault-extract/i then "vault_extractor"
      when /vault-sanitize/i then "vault_sanitizer"
      when /vault-recon/i then "recon_ops"
      when /ledger/i then "ledger_coder"
      when /ruby-coding|ruby_coder/i then "ruby_coder"
      when /frontend-coding|frontend_coder/i then "frontend_coder"
      when /hotwire-coding|hotwire_coder/i then "hotwire_coder"
      when /pii/i then "sanitizer"
      when /ocr-extraction|ocr/i then "extractor"
      when /triage|email/i then "triager"
      when /ikigai|crm/i then "crm_ops"
      else "coder"
      end
    end

    def self.scored_task?(task)
      return false if task["invalid"] == true
      return false if task.key?("scored") && task["scored"] == false
      return false if task["dry_run"] == true

      true
    end

    # Phase 3: lab scenarios may require matching oracle-pass + nop-fail artifacts
    # under ALPHA_ROOT/baselines/<scenario_id>/ before qualification can succeed.
    def self.missing_baseline_reason(scenario_id)
      require "json"
      dir = File.join(Alpha.config.root, "baselines", scenario_id.to_s)
      unless File.directory?(dir)
        return "require_baselines: missing baselines/#{scenario_id}/ (oracle-pass + nop-fail)"
      end

      oracles = Dir[File.join(dir, "oracle-pass__*.json")]
      nops = Dir[File.join(dir, "nop-fail__*.json")]
      return "require_baselines: no oracle-pass/nop-fail artifacts under baselines/#{scenario_id}/" if oracles.empty? || nops.empty?

      ok_pair = false
      oracles.each do |opath|
        key = File.basename(opath).sub(/\Aoracle-pass__/, "")
        npath = File.join(dir, "nop-fail__#{key}")
        next unless File.file?(npath)

        begin
          od = JSON.parse(File.read(opath))
          nd = JSON.parse(File.read(npath))
        rescue JSON::ParserError
          next
        end
        next unless od["observed_ok"] == true && nd["observed_ok"] == true
        next unless od["scenario_hash"].to_s == nd["scenario_hash"].to_s
        next unless od["harness_rev"].to_s == nd["harness_rev"].to_s

        ok_pair = true
        break
      end

      return nil if ok_pair

      "require_baselines: no matching observed_ok oracle-pass + nop-fail pair for #{scenario_id}"
    end

    def self.pass_at_1_rate(tasks, kind:)
      selected = tasks.select { |t| t["kind"].to_s == kind }
      # Absent kind is N/A (do not fail that threshold). Empty scored suite is
      # rejected separately in evaluate().
      return 1.0 if selected.empty?

      passes = selected.count { |t| truthy_pass_at_1?(t["pass_at_1"]) }
      passes.to_f / selected.size
    end

    def self.highest_passed_rung(tasks)
      rungs = tasks.select { |t| truthy_pass_at_1?(t["pass_at_1"]) && t["rung"] }.map { |t| t["rung"] }
      return nil if rungs.empty?

      Alpha::Rung.max(*rungs)
    end

    def self.mean_credit(tasks)
      graded = tasks.select { |t| t["kind"].to_s == "graded" }
      return 0.0 if graded.empty?

      values = graded.map { |t| t["credit"].nil? ? (truthy_pass_at_1?(t["pass_at_1"]) ? 1.0 : 0.0) : t["credit"].to_f }
      (values.sum / values.size).round(2)
    end

    def self.failure_histogram(tasks)
      hist = Hash.new(0)
      tasks.each { |t| hist[(t["failure_class"] || "unknown").to_s] += 1 }
      hist
    end

    def self.ship_skills(tasks)
      by_skill = tasks.group_by { |t| t["skill"].to_s.empty? ? "general" : t["skill"].to_s }
      by_skill.map do |skill, rows|
        rate = if rows.empty?
          1.0
        else
          rows.count { |t| truthy_pass_at_1?(t["pass_at_1"]) }.to_f / rows.size
        end
        graded_rows = rows.select { |t| t["kind"].to_s == "graded" }
        {
          "skill" => skill,
          "max_rung" => highest_passed_rung(rows),
          "pass_at_1" => rate.round(2),
          "credit_mean" => mean_credit(graded_rows.empty? ? rows : graded_rows)
        }
      end
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
