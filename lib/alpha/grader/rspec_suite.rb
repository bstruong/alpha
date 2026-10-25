# frozen_string_literal: true

require "fileutils"

module Alpha
  module Grader
    # Runs `bundle exec rspec` (or task-specific verifier spec) inside the sandbox,
    # plus optional stable_except path drift verification, AST mechanism checks,
    # and seed-mutation verification for agent-authored specs.
    class RSpecSuite < Base
      def call(sandbox:, task:, check_stability: false)
        syntax_res = sandbox.respond_to?(:check_ruby_syntax) ? sandbox.check_ruby_syntax : { ok: true, errors: [] }
        if !syntax_res[:ok]
          return Result.new(
            name: "RSpecSuite",
            pass: false,
            detail: {
              syntax_ok: false,
              syntax_errors: syntax_res[:errors],
              rspec_test: false,
              rspec_output: syntax_res[:output],
              verifier_ok: false,
              verifier_output: nil,
              drifted: []
            }
          )
        end

        rspec_res = run_rspec(sandbox)
        verifier_res = task.verifier_path ? run_verifier(sandbox, task) : nil
        drifted = check_stability && task.stable_except.any? ? sandbox.drifted_files(task.stable_except) : []
        ast_violations = check_ast_constraints(sandbox, task)
        mutation_res = check_seed_mutation(sandbox, task)

        passed = rspec_res[:ok] &&
                 (verifier_res.nil? || verifier_res[:ok]) &&
                 drifted.empty? &&
                 ast_violations.empty? &&
                 (mutation_res.nil? || mutation_res[:ok])

        detail = {
          syntax_ok: true,
          syntax_errors: [],
          rspec_test: rspec_res[:ok],
          rspec_output: rspec_res[:output],
          verifier_ok: verifier_res ? verifier_res[:ok] : nil,
          verifier_output: verifier_res ? verifier_res[:output] : nil,
          drifted: drifted
        }
        detail[:violations] = ast_violations if ast_violations.any?
        if mutation_res
          detail[:mutation_ok] = mutation_res[:ok]
          detail[:mutation_output] = mutation_res[:output]
        end

        Result.new(name: "RSpecSuite", pass: passed, detail: detail)
      end

      private
        def run_rspec(sandbox, timeout_s: DEFAULT_COMMAND_TIMEOUT)
          res = nil
          sandbox.run_in_clean_env do
            cmd = File.file?(File.join(sandbox.path, "bin", "rspec")) ? ["bin/rspec"] : ["bundle", "exec", "rspec"]
            res = run_command_with_timeout(sandbox.child_env, *cmd, chdir: sandbox.path, timeout_s: timeout_s)
          end
          res
        end

        def run_verifier(sandbox, task, timeout_s: DEFAULT_COMMAND_TIMEOUT)
          dest = File.join(sandbox.path, "tmp", "verification_spec.rb")
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(task.verifier_path, dest)
          res = nil
          sandbox.run_in_clean_env do
            cmd = File.file?(File.join(sandbox.path, "bin", "rspec")) ? ["bin/rspec", dest] : ["bundle", "exec", "rspec", dest]
            res = run_command_with_timeout(sandbox.child_env, *cmd, chdir: sandbox.path, timeout_s: timeout_s)
          end
          res
        end

        def check_ast_constraints(sandbox, task)
          has_task_ast_rules =
            (task.respond_to?(:denied_constants) && Array(task.denied_constants).any?) ||
            (task.respond_to?(:denied_keywords) && Array(task.denied_keywords).any?) ||
            (task.respond_to?(:denied_defs) && Array(task.denied_defs).any?) ||
            (task.respond_to?(:required_calls) && Array(task.required_calls).any?)

          if has_task_ast_rules
            AstDeny.new.call(sandbox: sandbox, task: task).detail[:violations]
          else
            AstDeny.detect_vacuous_asserts(sandbox.path)
          end
        end

        def check_seed_mutation(sandbox, task, timeout_s: DEFAULT_COMMAND_TIMEOUT)
          return nil unless task.respond_to?(:verify_test_fails_on_seed?) && task.verify_test_fails_on_seed?
          return nil unless sandbox.respond_to?(:seeded_path) && File.directory?(sandbox.seeded_path)

          modified_specs = if sandbox.respond_to?(:modified_ruby_files)
            sandbox.modified_ruby_files.select { |f| f.start_with?("spec/") && f.end_with?("_spec.rb") }
          else
            []
          end

          if modified_specs.empty?
            return {
              ok: false,
              output: "verify_test_fails_on_seed requires at least one modified spec/*_spec.rb file, but none were modified."
            }
          end

          modified_specs.each do |rel_spec|
            agent_spec_path = File.join(sandbox.path, rel_spec)
            cmd = if File.file?(File.join(sandbox.seeded_path, "bin", "rspec"))
              [ "bin/rspec", agent_spec_path ]
            else
              [ "bundle", "exec", "rspec", agent_spec_path ]
            end

            res = nil
            sandbox.run_in_clean_env do
              res = run_command_with_timeout(
                sandbox.child_env,
                *cmd,
                chdir: sandbox.seeded_path,
                timeout_s: timeout_s
              )
            end

            if res[:ok]
              return {
                ok: false,
                output: "Agent spec #{rel_spec} passed against unpatched seed code (expected failure to prove regression coverage)."
              }
            end
          end

          { ok: true, output: "Modified specs failed on unpatched seed as expected." }
        end
    end
  end
end
