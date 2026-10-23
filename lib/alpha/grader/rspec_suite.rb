# frozen_string_literal: true

require "fileutils"

module Alpha
  module Grader
    # Runs `bundle exec rspec` (or task-specific verifier spec) inside the sandbox,
    # plus optional stable_except path drift verification.
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

        passed = rspec_res[:ok] && (verifier_res.nil? || verifier_res[:ok]) && drifted.empty?

        detail = {
          syntax_ok: true,
          syntax_errors: [],
          rspec_test: rspec_res[:ok],
          rspec_output: rspec_res[:output],
          verifier_ok: verifier_res ? verifier_res[:ok] : nil,
          verifier_output: verifier_res ? verifier_res[:output] : nil,
          drifted: drifted
        }

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
    end
  end
end
