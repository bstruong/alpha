# frozen_string_literal: true

module Alpha
  # Interface for running an agent turn against a sandbox.
  module Executor
    Result = Data.define(
      :exit_reason,
      :timed_out,
      :wall_ms,
      :tool_calls,
      :prompt_tokens,
      :completion_tokens,
      :log_path
    )
  end
end
