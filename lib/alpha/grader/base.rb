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
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_s

          loop do
            _pid, status = Process.wait2(wait_thr.pid, Process::WNOHANG)
            if status
              out = stdout.read rescue ""
              return { ok: status.success?, output: out, status: status.exitstatus }
            end

            if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
              begin
                pgid = Process.getpgid(wait_thr.pid) rescue wait_thr.pid
                Process.kill("-TERM", pgid)
                sleep 0.1
                Process.kill("-KILL", pgid) if Process.wait2(wait_thr.pid, Process::WNOHANG).nil?
              rescue StandardError
              end
              break
            end
            sleep 0.05
          end

          { ok: false, output: "Command timed out after #{timeout_s}s: #{cmd.join(' ')}", status: 124 }
        end
      rescue StandardError => e
        { ok: false, output: "Execution error: #{e.message}", status: 1 }
      end
    end
  end
end
