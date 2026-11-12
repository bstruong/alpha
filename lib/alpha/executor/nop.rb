# frozen_string_literal: true

module Alpha
  module Executor
    # Integrity agent: performs no edits. Graded tasks must score 0.
    class Nop < Base
      def call(task:, sandbox:, inference_target: nil, profile: nil,
               log_path: nil, telemetry_path: nil, timeout_s: 30,
               max_tool_calls: nil)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        # Leave sandbox untouched — empty agent work.
        Result.new(
          exit_reason: "nop",
          timed_out: false,
          wall_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
          tool_calls: 0,
          prompt_tokens: 0,
          completion_tokens: 0,
          log_path: log_path
        )
      end
    end
  end
end

Alpha::Executor.register("nop", Alpha::Executor::Nop)
