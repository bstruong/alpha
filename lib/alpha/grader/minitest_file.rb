# frozen_string_literal: true

require "fileutils"
require "rbconfig"

module Alpha
  module Grader
    # Runs the base Minitest suite (`bin/rails test` or `rake test`) and the task's
    # `verification_test.rb` (when present) inside the sandbox, plus optional
    # `stable_except` path drift verification, AST mechanism checks, and
    # seed-mutation verification for agent-authored tests.
    class MinitestFile < Base
      def call(sandbox:, task:, check_stability: false)
        syntax_res = sandbox.respond_to?(:check_ruby_syntax) ? sandbox.check_ruby_syntax : { ok: true, errors: [] }
        if !syntax_res[:ok]
          return Result.new(
            name: "MinitestFile",
            pass: false,
            detail: {
              syntax_ok: false,
              syntax_errors: syntax_res[:errors],
              rails_test: false,
              rails_output: syntax_res[:output],
              verifier_ok: false,
              verifier_output: nil,
              checks: {},
              drifted: []
            }
          )
        end

        rails_res = run_rails_test(sandbox)
        verifier_res = task.verifier_path ? run_verifier(sandbox, task) : nil
        drifted = check_stability && task.stable_except.any? ? sandbox.drifted_files(task.stable_except) : []
        ast_violations = check_ast_constraints(sandbox, task)
        mutation_res = check_seed_mutation(sandbox, task)

        passed = rails_res[:ok] &&
                 (verifier_res.nil? || verifier_res[:ok]) &&
                 drifted.empty? &&
                 ast_violations.empty? &&
                 (mutation_res.nil? || mutation_res[:ok])

        detail = {
          syntax_ok: true,
          syntax_errors: [],
          rails_test: rails_res[:ok],
          rails_output: rails_res[:output],
          verifier_ok: verifier_res ? verifier_res[:ok] : nil,
          verifier_output: verifier_res ? verifier_res[:output] : nil,
          checks: verifier_res ? verifier_res[:checks] : {},
          drifted: drifted
        }
        detail[:violations] = ast_violations if ast_violations.any?
        if mutation_res
          detail[:mutation_ok] = mutation_res[:ok]
          detail[:mutation_output] = mutation_res[:output]
        end

        Result.new(name: "MinitestFile", pass: passed, detail: detail)
      end

      private
        def run_rails_test(sandbox, timeout_s: DEFAULT_COMMAND_TIMEOUT)
          rails_bin = File.join(sandbox.path, "bin", "rails")
          rakefile = File.join(sandbox.path, "Rakefile")
          gemfile = File.join(sandbox.path, "Gemfile")

          cmd = if File.file?(rails_bin)
            [ rails_bin, "test" ]
          elsif File.file?(rakefile) && File.file?(gemfile)
            [ "bundle", "exec", "rake", "test" ]
          elsif File.file?(rakefile)
            [ RbConfig.ruby, "-S", "rake", "test" ]
          end

          return { ok: false, output: "Missing bin/rails or Rakefile in sandbox", status: 127 } unless cmd

          res = nil
          sandbox.run_in_clean_env do
            res = run_command_with_timeout(sandbox.child_env, *cmd, chdir: sandbox.path, timeout_s: timeout_s)
          end
          res
        end

        def run_verifier(sandbox, task, timeout_s: DEFAULT_COMMAND_TIMEOUT)
          dest = File.join(sandbox.path, "tmp", "verification_test.rb")
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(task.verifier_path, dest)
          include_paths = [ File.join(sandbox.path, "lib"), File.join(sandbox.path, "test") ].join(File::PATH_SEPARATOR)
          gemfile = File.join(sandbox.path, "Gemfile")
          cmd = if File.file?(gemfile)
            [ "bundle", "exec", "ruby", "-I#{include_paths}", dest, "-v" ]
          else
            [ RbConfig.ruby, "-I#{include_paths}", dest, "-v" ]
          end

          res = nil
          sandbox.run_in_clean_env do
            res = run_command_with_timeout(
              sandbox.child_env,
              *cmd,
              chdir: sandbox.path,
              timeout_s: timeout_s
            )
          end
          res[:checks] = parse_minitest(res[:output]) if res[:output]
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

          modified_tests = if sandbox.respond_to?(:modified_ruby_files)
            sandbox.modified_ruby_files.select { |f| f.start_with?("test/") && f.end_with?("_test.rb") }
          else
            []
          end

          if modified_tests.empty?
            return {
              ok: false,
              output: "verify_test_fails_on_seed requires at least one modified test/*_test.rb file, but none were modified."
            }
          end

          include_paths = [ File.join(sandbox.seeded_path, "lib"), File.join(sandbox.seeded_path, "test") ].join(File::PATH_SEPARATOR)
          gemfile = File.join(sandbox.seeded_path, "Gemfile")

          modified_tests.each do |rel_test|
            agent_test_path = File.join(sandbox.path, rel_test)
            cmd = if File.file?(gemfile)
              [ "bundle", "exec", "ruby", "-I#{include_paths}", agent_test_path ]
            else
              [ RbConfig.ruby, "-I#{include_paths}", agent_test_path ]
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
                output: "Agent test #{rel_test} passed against unpatched seed code (expected failure to prove regression coverage)."
              }
            end
          end

          { ok: true, output: "Modified tests failed on unpatched seed as expected." }
        end

        def parse_minitest(output)
          checks = {}
          output.each_line do |line|
            next unless (match = line.match(/^(\S+) = [\d.]+ s = ([.FE])$/))

            checks[match[1]] = match[2] == "." ? "pass" : "fail"
          end
          checks
        end
    end
  end
end
