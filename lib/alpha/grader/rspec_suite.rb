# frozen_string_literal: true

require "fileutils"
require "open3"

module Alpha
  module Grader
    # Runs `bundle exec rspec` (or task-specific verifier spec) inside the sandbox,
    # plus optional stable_except path drift verification.
    class RSpecSuite < Base
      def call(sandbox:, task:, check_stability: false)
        rspec_res = run_rspec(sandbox)
        verifier_res = task.verifier_path ? run_verifier(sandbox, task) : nil
        drifted = check_stability && task.stable_except.any? ? sandbox.drifted_files(task.stable_except) : []

        passed = rspec_res[:ok] && (verifier_res.nil? || verifier_res[:ok]) && drifted.empty?

        detail = {
          rspec_test: rspec_res[:ok],
          rspec_output: rspec_res[:output],
          verifier_ok: verifier_res ? verifier_res[:ok] : nil,
          verifier_output: verifier_res ? verifier_res[:output] : nil,
          drifted: drifted
        }

        Result.new(name: "RSpecSuite", pass: passed, detail: detail)
      end

      private
        def run_rspec(sandbox)
          out = nil
          status = nil
          sandbox.run_in_clean_env do
            cmd = File.file?(File.join(sandbox.path, "bin", "rspec")) ? ["bin/rspec"] : ["bundle", "exec", "rspec"]
            out, status = Open3.capture2e(sandbox.child_env, *cmd, chdir: sandbox.path)
          end
          { ok: status.success?, output: out, status: status.exitstatus }
        end

        def run_verifier(sandbox, task)
          dest = File.join(sandbox.path, "tmp", "verification_spec.rb")
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(task.verifier_path, dest)
          out = nil
          status = nil
          sandbox.run_in_clean_env do
            cmd = File.file?(File.join(sandbox.path, "bin", "rspec")) ? ["bin/rspec", dest] : ["bundle", "exec", "rspec", dest]
            out, status = Open3.capture2e(sandbox.child_env, *cmd, chdir: sandbox.path)
          end
          { ok: status.success?, output: out, status: status.exitstatus }
        end
    end
  end
end
