# frozen_string_literal: true

module Alpha
  module Executor
    # Headless Pi: `pi --mode rpc --no-session` with pgroup: true.
    class PiRpc < Base
      def call(_task:, _sandbox:, _inference_target:, **_kwargs)
        # TODO(you):
        # - Process.spawn(..., pgroup: true)
        # - non-blocking stdout drain (avoid pipe deadlock)
        # - kill process group on timeout
        # - return a result hash: tool_calls, tokens, wall_ms, exit_reason
        raise NotImplementedError, "#{self.class}##{__method__}"
      end
    end
  end
end
