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

    @registry = {}

    def self.register(name, klass)
      @registry[name.to_s] = klass
    end

    def self.resolve(type)
      key = type.to_s
      return @registry[key].new if @registry.key?(key)

      case key
      when "openai_chat_completions", "openai", "stateless"
        OpenAIChatCompletions.new
      else
        PiRpc.new
      end
    end
  end
end

require_relative "executor/base"
require_relative "executor/pi_rpc"
require_relative "executor/openai_chat_completions"
