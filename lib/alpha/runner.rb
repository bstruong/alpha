# frozen_string_literal: true

module Alpha
  # Orchestrates: resolve scenario → sandbox → executor → graders → metrics → report.
  # This is the main critical path — implement last once the pieces above work in isolation.
  class Runner
    def initialize(scenario:, inference_target:, executor: Executor::PiRpc.new)
      @scenario = scenario
      @inference_target = inference_target
      @executor = executor
    end

    def call
      # TODO(you): loop tasks, enforce budgets, short-circuit on failed gates,
      # persist EvalRun / TaskResult if you want DB mirrors, then Report.build
      raise NotImplementedError, "#{self.class}##{__method__}"
    end
  end
end
