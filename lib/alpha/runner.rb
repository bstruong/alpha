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

    def call(trials: 1, keep_sandbox: false, dry_run: false, no_gate_halt: false, max_turns: 1, thinking: "low")
      run_id = "#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{scenario.id}"
      puts "=== Alpha Run: #{run_id} ==="
      puts "Scenario: #{scenario.id} | Model: #{inference_target&.model_id} | Profile: #{scenario.profile.name}"
      puts "Thinking: #{thinking} | Max Turns: #{max_turns} #{'(Self-Repair Enabled)' if max_turns > 1}"
      puts "Tasks: #{scenario.tasks.map(&:name).join(", ")}"
      puts ""

      task_records = []
      gates_ok = true

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

          if dry_run
            puts "DRY RUN (sandbox & prompt verified)"
            task_records << {
              task_name: task.name,
              kind: task.kind,
              trial: trial_num,
              pass: true,
              pass_at_1: true,
              repaired: false,
              turns: 1,
              thinking_level: task.thinking || thinking,
              tool_calls: 0,
              prompt_tokens: 0,
              completion_tokens: 0,
              wall_ms: 0,
              graders: []
            }
            next
          end

          trial_record = execute_trial(
            task, trial_num, run_id,
            keep_sandbox: keep_sandbox,
            max_turns: max_turns,
            thinking: task.thinking || thinking
          )
          passed = trial_record[:pass]
          repaired = trial_record[:repaired]
          status_str = if repaired
            "✓ REPAIRED (Turn 2)"
          elsif passed
            "✓ PASS"
          else
            "✗ FAIL"
          end
          puts "#{status_str} in #{(trial_record[:wall_ms] / 1000.0).round(1)}s (tools: #{trial_record[:tool_calls]}, turns: #{trial_record[:turns]})"

          task_records << trial_record
          gates_ok = false if task.gate? && !passed
        end

        break if task.gate? && !gates_ok && !no_gate_halt
      end

      report_res = Report.build(
        run_id,
        scenario: scenario,
        model_id: inference_target&.model_id || "none",
        prompt_preset: scenario.profile.name,
        inference_target: inference_target,
        task_records: task_records
      )

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

      def execute_trial(task, trial_num, run_id, keep_sandbox: false, max_turns: 1, thinking: "low")
        inference_target&.erase_slots!

        active_task = thinking ? task.with_thinking(thinking) : task
        sandbox = Sandbox.provision(active_task, library_dir: scenario.base_app_dir)
        total_tool_calls = 0
        total_prompt_tokens = 0
        total_completion_tokens = 0
        total_wall_ms = 0
        turn_history = []
        current_turn = 1

        active_executor = resolve_executor(active_task)
        active_grader = resolve_grader(active_task)

        task_max_tool_calls = (active_task.respond_to?(:max_tool_calls) && active_task.max_tool_calls) ||
                              scenario.budget[:max_tool_calls]

        exec_res = active_executor.call(
          task: active_task,
          sandbox: sandbox,
          inference_target: inference_target,
          profile: scenario.profile,
          timeout_s: scenario.budget[:wall_seconds],
          max_tool_calls: task_max_tool_calls
        )

        total_tool_calls += exec_res.tool_calls
        total_prompt_tokens += exec_res.prompt_tokens
        total_completion_tokens += exec_res.completion_tokens
        total_wall_ms += exec_res.wall_ms

        sandbox.restore_protected!(active_task)
        patch_path = File.join(sandbox.work_dir, "agent.patch")
        sandbox.diff_from_seeded(patch_path)

        grader_res = active_grader.call(sandbox: sandbox, task: active_task, check_stability: true)

        turn_history << {
          turn: 1,
          pass: grader_res.pass,
          tool_calls: exec_res.tool_calls,
          wall_ms: exec_res.wall_ms,
          detail: grader_res.detail
        }

        # Multi-Turn Self-Repair (Turn 2)
        if !grader_res.pass && max_turns > 1 && !exec_res.timed_out
          current_turn = 2
          failure_feedback = extract_failure_summary(grader_res.detail)
          repair_task = active_task.with_repair_feedback(failure_feedback)

          remaining_tool_calls = task_max_tool_calls ? [task_max_tool_calls - total_tool_calls, 1].max : nil
          exec_res_2 = active_executor.call(
            task: repair_task,
            sandbox: sandbox,
            inference_target: inference_target,
            profile: scenario.profile,
            timeout_s: scenario.budget[:wall_seconds],
            max_tool_calls: remaining_tool_calls
          )

          total_tool_calls += exec_res_2.tool_calls
          total_prompt_tokens += exec_res_2.prompt_tokens
          total_completion_tokens += exec_res_2.completion_tokens
          total_wall_ms += exec_res_2.wall_ms

          sandbox.restore_protected!(active_task)
          sandbox.diff_from_seeded(patch_path)

          grader_res = active_grader.call(sandbox: sandbox, task: active_task, check_stability: true)

          turn_history << {
            turn: 2,
            pass: grader_res.pass,
            tool_calls: exec_res_2.tool_calls,
            wall_ms: exec_res_2.wall_ms,
            detail: grader_res.detail
          }
        end

        pass_at_1 = turn_history.first[:pass]
        budget_exceeded = task_max_tool_calls && total_tool_calls > task_max_tool_calls
        final_pass = grader_res.pass && !budget_exceeded
        repaired = !pass_at_1 && final_pass

        record = {
          task_name: task.name,
          kind: task.kind,
          trial: trial_num,
          pass: final_pass,
          pass_at_1: pass_at_1,
          repaired: repaired,
          turns: current_turn,
          thinking_level: thinking,
          tool_calls: total_tool_calls,
          prompt_tokens: total_prompt_tokens,
          completion_tokens: total_completion_tokens,
          wall_ms: total_wall_ms,
          timed_out: exec_res.timed_out,
          exit_reason: exec_res.exit_reason,
          turn_history: turn_history,
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
          repaired: false,
          turns: 1,
          thinking_level: thinking,
          tool_calls: 0,
          prompt_tokens: 0,
          completion_tokens: 0,
          wall_ms: 0,
          timed_out: false,
          exit_reason: "error: #{e.message}",
          turn_history: [],
          graders: [ { name: "MinitestFile", pass: false, detail: { error: e.message } } ]
        }
      end

      def clean_test_output(raw_output, max_lines: 30)
        return "" if raw_output.nil? || raw_output.empty?

        lines = raw_output.to_s.lines
        filtered = lines.reject do |line|
          line.include?("/gems/") || line.include?("/bundle/") || line.include?("/.rbenv/") || line.include?("/mise/")
        end
        effective = filtered.empty? ? lines : filtered
        effective.last(max_lines).join
      end

      def extract_failure_summary(detail)
        return "" unless detail.is_a?(Hash)

        sections = []
        if detail[:syntax_errors] && Array(detail[:syntax_errors]).any?
          sections << "=== Ruby Syntax Errors ===\n#{detail[:syntax_errors].join("\n")}"
        end
        if detail[:violations] && Array(detail[:violations]).any?
          v_lines = detail[:violations].map do |v|
            if v.is_a?(Hash)
              "#{v[:file]}:#{v[:line]} - #{v[:reason] || v[:token] || v[:pattern]}"
            else
              v.to_s
            end
          end
          sections << "=== AST / Pattern Deny Violations ===\n#{v_lines.join("\n")}"
        end
        if detail[:rails_output] && !detail[:rails_test]
          sections << "=== Rails test output ===\n#{clean_test_output(detail[:rails_output])}"
        end
        if detail[:rspec_output] && !detail[:rspec_test]
          sections << "=== RSpec output ===\n#{clean_test_output(detail[:rspec_output])}"
        end
        if detail[:verifier_output] && detail[:verifier_ok] == false
          sections << "=== Verification test output ===\n#{clean_test_output(detail[:verifier_output])}"
        end
        if detail[:mutation_output] && detail[:mutation_ok] == false
          sections << "=== Test Mutation Check ===\n#{detail[:mutation_output]}"
        end
        if detail[:drifted] && Array(detail[:drifted]).any?
          sections << "=== Modified protected/forbidden files ===\n#{detail[:drifted].join(', ')}"
        end
        if detail[:error]
          sections << "=== Execution Error ===\n#{detail[:error]}"
        end
        sections.empty? ? detail.to_s : sections.join("\n\n")
      end

      def resolve_executor(task)
        type = task.executor_type || (scenario.respond_to?(:executor_type) && scenario.executor_type)
        if type
          Executor.resolve(type)
        else
          @executor || Executor.resolve(nil)
        end
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

        # 1. Seed check: should reproduce expected_seed (0 for graded, 1 for gate-boot)
        seed_grade = active_grader.call(sandbox: sandbox, task: task)
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
        [ true, "seed #{seed_reward} -> solution 1.0 (verified)" ]
      rescue StandardError => e
        sandbox&.teardown! unless keep_sandbox
        [ false, "exception: #{e.message}" ]
      end
  end
end
