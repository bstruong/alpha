# frozen_string_literal: true

module Alpha
  module Executor
    class Base
      def call(_task:, _sandbox:, _inference_target:, **_kwargs)
        # TODO(you): implement in a subclass (PiRpc, OpenAIChatCompletions, …)
        raise NotImplementedError, "#{self.class}##{__method__}"
      end
    end
  end
end
