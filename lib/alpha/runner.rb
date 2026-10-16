# frozen_string_literal: true

require "time"

module Alpha
  # Orchestrates: resolve scenario → sandbox → executor → graders → metrics → report.
  # Supports full AI model runs (#call) and fast zero-model verification (#oracle).
  class Runner
    attr_reader :scenario, :inference_target, :executor, :grader

    def initialize(scenario:, inference_target: nil, executor: Executor::PiRpc.new, grader: Grader::MinitestFile.new)
      @scenario = scenario
      @inference_target = inference_target
      @executor = executor
      @grader = grader
    end

    def call(trials: 1, keep_sandbox: false, dry_run: false)
      run_id = "#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{scenario.id}"
      puts "=== Alpha Run: #{run_id} ==="
      puts "Scenario: #{scenario.id} | Model: #{inference_target&.model_id} | Profile: #{scenario.profile.name}"
      puts "Tasks: #{scenario.tasks.map(&:name).join(", ")}"
      puts ""

      task_records = []
      gates_ok = true

      scenario.tasks.each_with_index do |task, idx|
        task_num = idx + 1
        total_tasks = scenario.tasks.size

        if task.gate? && !gates_ok
          puts "[#{task_num}/#{total_tasks}] #{task.name} (gate): SKIPPED (prior gate failed)"
          next
        end

        trials.times do |trial_idx|
          trial_num = trial_idx + 1
          print "[#{task_num}/#{total_tasks}] #{task.name} (#{task.kind}) trial #{trial_num}/#{trials} ... "
          $stdout.flush

          if dry_run
            puts "DRY RUN (sandbox & prompt verified)"
            task_records << {
              task_name: task.name,
              kind: task.kind,
              trial: trial_num,
              pass: true,
              pass_at_1: true,
              tool_calls: 0,
              prompt_tokens: 0,
              completion_tokens: 0,
              wall_ms: 0,
              graders: []
            }
            next
          end

          trial_record = execute_trial(task, trial_num, run_id, keep_sandbox: keep_sandbox)
          passed = trial_record[:pass]
          status_str = passed ? "✓ PASS" : "✗ FAIL"
          puts "#{status_str} in #{(trial_record[:wall_ms] / 1000.0).round(1)}s (tools: #{trial_record[:tool_calls]})"

          task_records << trial_record
          gates_ok = false if task.gate? && !passed
        end

        break if task.gate? && !gates_ok
      end

      report_res = Report.build(
        run_id,
        scenario: scenario,
        model_id: inference_target&.model_id || "none",
        prompt_preset: scenario.profile.name,
        inference_target: inference_target,
        task_records: task_records
      )

      sync_to_database(run_id, report_res[:payload], report_res[:summary_path], report_res[:report_path])

      puts ""
      puts "Summary written to: #{report_res[:summary_path]}"
      puts "Report written to:  #{report_res[:report_path]}"
      puts "Pass@1: #{report_res.dig(:payload, "aggregate", "pass_at_1")}"

      { ok: gates_ok, report: report_res }
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
      def execute_trial(task, trial_num, run_id, keep_sandbox: false)
        inference_target&.erase_slots!

        sandbox = Sandbox.provision(task, library_dir: scenario.base_app_dir)
        exec_res = executor.call(
          task: task,
          sandbox: sandbox,
          inference_target: inference_target,
          profile: scenario.profile,
          timeout_s: scenario.budget[:wall_seconds]
        )

        sandbox.restore_protected!(task)
        patch_path = File.join(sandbox.work_dir, "agent.patch")
        sandbox.diff_from_seeded(patch_path)

        grader_res = grader.call(sandbox: sandbox, task: task, check_stability: true)

        record = {
          task_name: task.name,
          kind: task.kind,
          trial: trial_num,
          pass: grader_res.pass,
          pass_at_1: grader_res.pass,
          tool_calls: exec_res.tool_calls,
          prompt_tokens: exec_res.prompt_tokens,
          completion_tokens: exec_res.completion_tokens,
          wall_ms: exec_res.wall_ms,
          timed_out: exec_res.timed_out,
          exit_reason: exec_res.exit_reason,
          graders: [ { name: grader_res.name, pass: grader_res.pass, detail: grader_res.detail } ]
        }

        MetricRecord.write!(run_id, record)
        sandbox.teardown! unless keep_sandbox

        record
      rescue StandardError => e
        sandbox&.teardown! unless keep_sandbox
        {
          task_name: task.name,
          kind: task.kind,
          trial: trial_num,
          pass: false,
          pass_at_1: false,
          tool_calls: 0,
          prompt_tokens: 0,
          completion_tokens: 0,
          wall_ms: 0,
          timed_out: false,
          exit_reason: "error: #{e.message}",
          graders: [ { name: "MinitestFile", pass: false, detail: { error: e.message } } ]
        }
      end

      def check_task_oracle(task, keep_sandbox: false)
        sandbox = Sandbox.provision(task, library_dir: scenario.base_app_dir)

        # 1. Seed check: should reproduce expected_seed (0 for graded, 1 for gate-boot)
        seed_grade = grader.call(sandbox: sandbox, task: task)
        seed_reward = seed_grade.pass ? 1 : 0
        if seed_reward != task.expected_seed
          sandbox.teardown! unless keep_sandbox
          return [ false, "seed reward #{seed_reward}, expected #{task.expected_seed}" ]
        end

        return [ true, "boot reward 1" ] unless task.solution_patch

        # 2. Solution check: applying solution.patch should pass
        unless sandbox.apply_patch!(task.solution_patch)
          sandbox.teardown! unless keep_sandbox
          return [ false, "solution.patch did not apply" ]
        end

        sol_grade = grader.call(sandbox: sandbox, task: task, check_stability: true)
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
        [ true, "seed #{seed_reward} -> solution 1.0 (verified)" ]
      rescue StandardError => e
        sandbox&.teardown! unless keep_sandbox
        [ false, "exception: #{e.message}" ]
      end

      def sync_to_database(run_id, payload, summary_path, report_path)
        return unless defined?(EvalRun) && EvalRun.respond_to?(:table_exists?) && EvalRun.table_exists?

        eval_run = EvalRun.find_or_initialize_by(run_id: run_id)
        eval_run.scenario_id = payload["scenario"]
        eval_run.model_id = payload["model_id"]
        eval_run.prompt_preset = payload["prompt_preset"]
        eval_run.engine_preset = payload.dig("inference", "preset")
        eval_run.pass_at_1 = payload.dig("aggregate", "pass_at_1")
        eval_run.status = eval_run.pass_at_1 && eval_run.pass_at_1 >= 0.7 ? "completed" : "failed"
        eval_run.summary_path = summary_path
        eval_run.report_path = report_path
        eval_run.started_at ||= Time.now.utc
        eval_run.finished_at = Time.now.utc
        eval_run.save!

        Array(payload["tasks"]).each do |t|
          tr = eval_run.task_results.find_or_initialize_by(task_name: t["name"])
          tr.pass = t["pass"]
          tr.tool_calls = t["tool_calls"]
          tr.prompt_tokens = t["prompt_tokens"]
          tr.completion_tokens = t["completion_tokens"]
          tr.wall_ms = t["wall_ms"]
          tr.grader_detail = t["graders"]
          tr.save!
        end
      rescue StandardError => e
        warn "ActiveRecord DB sync skipped: #{e.message}"
      end
  end
end
