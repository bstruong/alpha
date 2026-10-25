# frozen_string_literal: true

require "open3"

module Alpha
  module Grader
    class Base
      DEFAULT_COMMAND_TIMEOUT = 60

      def call(_sandbox:, _task:)
        raise NotImplementedError, "#{self.class}##{__method__}"
      end

      def run_command_with_timeout(env, *cmd, chdir:, timeout_s: DEFAULT_COMMAND_TIMEOUT)
        Open3.popen2e(env, *cmd, chdir: chdir, pgroup: true) do |stdin, stdout, wait_thr|
          stdin.close
          reader = Thread.new { stdout.read rescue "" }
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_s

          loop do
            if wait_thr.join(0.05)
              status = wait_thr.value
              out = reader.value
              return { ok: status.success?, output: out, status: status.exitstatus }
            end

            if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
              begin
                pgid = Process.getpgid(wait_thr.pid) rescue wait_thr.pid
                Process.kill("-TERM", pgid)
                unless wait_thr.join(0.1)
                  Process.kill("-KILL", pgid)
                  wait_thr.join(0.1)
                end
              rescue StandardError
              end
              reader.kill
              break
            end
          end

          { ok: false, output: "Command timed out after #{timeout_s}s: #{cmd.join(' ')}", status: 124 }
        end
      rescue StandardError => e
        { ok: false, output: "Execution error: #{e.message}", status: 1 }
      end
    end
  end
end
