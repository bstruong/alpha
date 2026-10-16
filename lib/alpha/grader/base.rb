# frozen_string_literal: true

module Alpha
  module Grader
    class Base
      def call(_sandbox:, _task:)
        raise NotImplementedError, "#{self.class}##{__method__}"
      end
    end
  end
end
