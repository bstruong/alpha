# frozen_string_literal: true

require "fileutils"

module Alpha
  module Grader
    # Runs both the base Rails test suite (`bin/rails test`) and the task's
    # `verification_test.rb` (when present) inside the sandbox, plus optional
    # `stable_except` path drift verification.
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

        passed = rails_res[:ok] && (verifier_res.nil? || verifier_res[:ok]) && drifted.empty?

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

        Result.new(name: "MinitestFile", pass: passed, detail: detail)
      end

      private
        def run_rails_test(sandbox, timeout_s: DEFAULT_COMMAND_TIMEOUT)
          rails_bin = File.join(sandbox.path, "bin", "rails")
          return { ok: false, output: "Missing bin/rails in sandbox", status: 127 } unless File.file?(rails_bin)

          res = nil
          sandbox.run_in_clean_env do
            res = run_command_with_timeout(sandbox.child_env, rails_bin, "test", chdir: sandbox.path, timeout_s: timeout_s)
          end
          res
        end

        def run_verifier(sandbox, task, timeout_s: DEFAULT_COMMAND_TIMEOUT)
          dest = File.join(sandbox.path, "tmp", "verification_test.rb")
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(task.verifier_path, dest)
          res = nil
          sandbox.run_in_clean_env do
            res = run_command_with_timeout(
              sandbox.child_env,
              "bundle", "exec", "ruby", "-I#{File.join(sandbox.path, "test")}", dest, "-v",
              chdir: sandbox.path,
              timeout_s: timeout_s
            )
          end
          res[:checks] = parse_minitest(res[:output]) if res[:output]
          res
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
