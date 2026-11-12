# frozen_string_literal: true

require "time"

module Alpha
  # Orchestrates: resolve scenario → sandbox → executor → graders → metrics → report.
  # Supports full AI model runs (#call) and fast zero-model verification (#oracle).
  class Runner
    attr_reader :scenario, :inference_target, :executor, :grader

    def initialize(scenario:, inference_target: nil, executor: nil, grader: Grader::MinitestFile.new,
                   suite_complete: true)
      @scenario = scenario
      @inference_target = inference_target
      @executor = executor
      @grader = grader
      @suite_complete = suite_complete
    end

    def call(trials: 1, keep_sandbox: false, dry_run: false, no_gate_halt: false, thinking: "low")
      run_id = "#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{scenario.id}"
      puts "=== Alpha Run: #{run_id} ==="
      puts "Scenario: #{scenario.id} | Model: #{inference_target&.model_id} | Profile: #{scenario.profile.name}"
      puts "Thinking: #{thinking} | Suite complete: #{@suite_complete}"
      puts "Tasks: #{scenario.tasks.map(&:name).join(", ")}"
      puts ""

      if dry_run
        return planning_only_run(run_id, thinking: thinking)
      end

      task_records = []
      gates_ok = true
      infra_invalid = false

      scenario.tasks.each_with_index do |task, idx|
        task_num = idx + 1
        total_tasks = scenario.tasks.size

        if task.gate? && !gates_ok && !no_gate_halt
          puts "[#{task_num}/#{total_tasks}] #{task.name} (gate): SKIPPED (prior gate failed)"
          next
        end

        trials.times do |trial_idx|
          trial_num = trial_idx + 1
          print "[#{task_num}/#{total_tasks}] #{task.name} (#{task.kind}) trial #{trial_num}/#{trials} ... "
          $stdout.flush

          trial_record = execute_trial(
            task, trial_num, run_id,
            keep_sandbox: keep_sandbox,
            thinking: task.thinking || thinking
          )
          passed = trial_record[:pass]
          status_str = if trial_record[:invalid]
            infra_invalid = true
            "⚠ INVALID (#{trial_record[:invalid_reason]})"
          elsif passed
            "✓ PASS"
          else
            "✗ FAIL (#{trial_record[:failure_class]})"
          end
          puts "#{status_str} in #{(trial_record[:wall_ms] / 1000.0).round(1)}s (tools: #{trial_record[:tool_calls]})"

          task_records << trial_record
          gates_ok = false if task.gate? && (!passed || trial_record[:invalid])
        end

        break if task.gate? && !gates_ok && !no_gate_halt
      end

      report_res = Report.build(
        run_id,
        scenario: scenario,
        model_id: inference_target&.model_id || (@executor.is_a?(Executor::Nop) ? "nop" : "none"),
        prompt_preset: scenario.profile.name,
        inference_target: inference_target || "none",
        task_records: task_records,
        suite_complete: @suite_complete,
        dry_run: false
      )

      status = report_res.dig(:payload, "status") || {}
      puts ""
      puts "Summary written to: #{report_res[:summary_path]}"
      puts "Report written to:  #{report_res[:report_path]}"
      puts "First-attempt success: #{report_res.dig(:payload, "aggregate", "pass_at_1")} " \
           "(#{report_res.dig(:payload, "aggregate", "tasks_passed")}/#{report_res.dig(:payload, "aggregate", "tasks_total")})"
      puts "Highest rung: #{report_res.dig(:payload, "aggregate", "highest_rung_passed") || "—"}"
      puts "Execution health: #{status["execution_health"]} | Gate: #{status["gate_status"]} | " \
           "Benchmark: #{status["benchmark_verdict"]}"

      campaign_ok = campaign_exit_ok?(status)
      { ok: campaign_ok, report: report_res, status: status, infra_invalid: infra_invalid }
    end

    def oracle(only_task: nil, keep_sandbox: false)
      puts "=== Alpha Oracle: #{scenario.id} (zero-model verification) ==="
      tasks = scenario.tasks
      tasks = tasks.select { |t| t.name == only_task.to_s } if only_task
      raise ArgumentError, "No task matching #{only_task.inspect}" if tasks.empty?

      all_passed = true

      tasks.each do |task|
        ok, detail = check_task_oracle(task, keep_sandbox: keep_sandbox)
        status_label = ok ? "✓ PASS" : "✗ FAIL"
        puts format("%-18s %s: %s", task.name, status_label, detail)
        all_passed = false unless ok
      end

      all_passed
    end

    private

      def planning_only_run(run_id, thinking:)
        puts "DRY RUN (planning only — no scored trials, not qualification-eligible)"
        scenario.tasks.each_with_index do |task, idx|
          puts "[#{idx + 1}/#{scenario.tasks.size}] #{task.name} (#{task.kind}) — prompt verified " \
               "(#{task.prompt(scenario.profile.name).bytesize} bytes)"
        end

        report_res = Report.build(
          run_id,
          scenario: scenario,
          model_id: inference_target&.model_id || "none",
          prompt_preset: scenario.profile.name,
          inference_target: inference_target || "none",
          task_records: [],
          suite_complete: false,
          dry_run: true
        )

        status = report_res.dig(:payload, "status") || {}
        puts ""
        puts "Planning summary written to: #{report_res[:summary_path]}"
        puts "Report written to:  #{report_res[:report_path]}"
        puts "Qualification eligible: false (dry-run)"

        { ok: true, report: report_res, status: status, infra_invalid: false }
      end

      def campaign_exit_ok?(status)
        return false if status["execution_health"] == "infrastructure_invalid"
        return false if status["gate_status"] == "failed"
        return false if status["benchmark_verdict"] == "fail"
        return false if status["benchmark_verdict"] == "incomplete" && @suite_complete

        true
      end

      def execute_trial(task, trial_num, run_id, keep_sandbox: false, thinking: "low")
        inference_target&.erase_slots!

        active_task = thinking ? task.with_thinking(thinking) : task
        sandbox = Sandbox.provision(active_task, library_dir: scenario.base_app_dir)

        active_executor = resolve_executor(active_task)
        active_grader = resolve_grader(active_task)

        task_max_tool_calls = (active_task.respond_to?(:max_tool_calls) && active_task.max_tool_calls) ||
                              scenario.budget[:max_tool_calls]
        timeout_s = (active_task.respond_to?(:wall_seconds) && active_task.wall_seconds) ||
                    scenario.budget[:wall_seconds]

        exec_res = active_executor.call(
          task: active_task,
          sandbox: sandbox,
          inference_target: inference_target,
          profile: scenario.profile,
          timeout_s: timeout_s,
          max_tool_calls: task_max_tool_calls
        )

        sandbox.restore_protected!(active_task)
        patch_path = File.join(sandbox.work_dir, "agent.patch")
        sandbox.diff_from_seeded(patch_path)
        agent_patch_empty = !File.file?(patch_path) || File.size(patch_path).zero? ||
                            File.read(patch_path).strip.empty?

        grader_res = active_grader.call(sandbox: sandbox, task: active_task, check_stability: true)

        pass_at_1 = grader_res.pass
        budget_exceeded = task_max_tool_calls && exec_res.tool_calls > task_max_tool_calls
        final_pass = grader_res.pass && !budget_exceeded
        credit = grader_res.respond_to?(:credit) ? grader_res.credit : (final_pass ? 1.0 : 0.0)

        outcome = TrialOutcome.classify(
          exit_reason: exec_res.exit_reason,
          timed_out: exec_res.timed_out,
          agent_patch_empty: agent_patch_empty,
          grader_detail: grader_res.detail
        )

        failure_class = FailureClass.classify(
          pass: final_pass && outcome[:scored],
          invalid: outcome[:invalid],
          invalid_reason: outcome[:invalid_reason],
          agent_patch_empty: agent_patch_empty,
          exit_reason: exec_res.exit_reason,
          timed_out: exec_res.timed_out,
          tool_budget_exceeded: budget_exceeded || exec_res.exit_reason == "tool_budget_exceeded",
          grader_detail: grader_res.detail,
          credit: credit
        )

        latency_budget_ms = task.respond_to?(:latency_budget_ms) ? task.latency_budget_ms : nil
        workflow_tier = task.respond_to?(:workflow_tier) ? task.workflow_tier : nil
        within_budget = if latency_budget_ms
          exec_res.wall_ms <= latency_budget_ms
        end

        record = {
          task_name: task.name,
          kind: task.kind,
          skill: task.skill,
          rung: task.rung,
          scaffold: task.scaffold,
          trial: trial_num,
          trial_id: "#{run_id}/#{task.name}/trial-#{trial_num}",
          pass: outcome[:scored] ? final_pass : false,
          pass_at_1: outcome[:scored] ? pass_at_1 : false,
          credit: outcome[:scored] ? credit : 0.0,
          scored: outcome[:scored],
          invalid: outcome[:invalid],
          invalid_reason: outcome[:invalid_reason],
          failure_class: failure_class,
          thinking_level: thinking,
          tool_calls: exec_res.tool_calls,
          prompt_tokens: exec_res.prompt_tokens,
          completion_tokens: exec_res.completion_tokens,
          wall_ms: exec_res.wall_ms,
          latency_budget_ms: latency_budget_ms,
          workflow_tier: workflow_tier,
          within_budget: within_budget,
          timed_out: exec_res.timed_out,
          exit_reason: exec_res.exit_reason,
          graders: [ {
            name: grader_res.name,
            pass: grader_res.pass,
            credit: credit,
            checks: grader_res.respond_to?(:checks) ? grader_res.checks : [],
            detail: grader_res.detail
          } ]
        }

        MetricRecord.write!(run_id, record)
        sandbox.teardown! unless keep_sandbox

        record
      rescue StandardError => e
        sandbox&.teardown! unless keep_sandbox
        {
          task_name: task.name,
          kind: task.kind,
          skill: task.skill,
          rung: task.rung,
          scaffold: task.scaffold,
          trial: trial_num,
          trial_id: "#{run_id}/#{task.name}/trial-#{trial_num}",
          pass: false,
          pass_at_1: false,
          credit: 0.0,
          scored: false,
          invalid: true,
          invalid_reason: "error: #{e.message}",
          failure_class: "infra",
          thinking_level: thinking,
          tool_calls: 0,
          prompt_tokens: 0,
          completion_tokens: 0,
          wall_ms: 0,
          timed_out: false,
          exit_reason: "error: #{e.message}",
          graders: [ { name: "Runner", pass: false, credit: 0.0, checks: [], detail: { error: e.message } } ]
        }
      end

      def resolve_executor(task)
        return @executor if @executor

        type = task.executor_type || (scenario.respond_to?(:executor_type) && scenario.executor_type)
        Executor.resolve(type)
      end

      def resolve_grader(task)
        type = task.grader_type || (scenario.respond_to?(:grader_type) && scenario.grader_type)
        if type
          Grader.resolve(type)
        else
          @grader || Grader.resolve(nil)
        end
      end

      def check_task_oracle(task, keep_sandbox: false)
        active_grader = resolve_grader(task)
        sandbox = Sandbox.provision(task, library_dir: scenario.base_app_dir)

        seed_grade = active_grader.call(sandbox: sandbox, task: task)
        seed_reward = seed_grade.pass ? 1 : 0
        if seed_reward != task.expected_seed
          sandbox.teardown! unless keep_sandbox
          return [ false, "seed reward #{seed_reward}, expected #{task.expected_seed}" ]
        end

        return [ true, "boot reward 1" ] unless task.solution_patch

        unless sandbox.apply_patch!(task.solution_patch)
          sandbox.teardown! unless keep_sandbox
          return [ false, "solution.patch did not apply" ]
        end

        # Re-prepare DB after solution so migration/schema restores are visible to graders.
        prepared, prepare_out = sandbox.prepare_db!
        unless prepared
          sandbox.teardown! unless keep_sandbox
          return [ false, "solution db:prepare failed: #{prepare_out}" ]
        end

        sol_grade = active_grader.call(sandbox: sandbox, task: task, check_stability: true)
        unless sol_grade.pass
          sandbox.teardown! unless keep_sandbox
          return [ false, "solution failed verification" ]
        end

        if task.stable_except.any?
          drifted = sandbox.drifted_files(task.stable_except)
          if drifted.any?
            sandbox.teardown! unless keep_sandbox
            return [ false, "solution touched forbidden files: #{drifted.join(", ")}" ]
          end
        end

        sandbox.teardown! unless keep_sandbox
        credit = sol_grade.respond_to?(:credit) ? sol_grade.credit : 1.0
        [ true, "seed #{seed_reward} -> solution #{credit} (verified)" ]
      rescue StandardError => e
        sandbox&.teardown! unless keep_sandbox
        [ false, "exception: #{e.message}" ]
      end
  end
end
