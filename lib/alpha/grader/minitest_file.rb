# frozen_string_literal: true

module Alpha
  module Grader
    class MinitestFile < Base
      def call(_sandbox:, _task:)
        # TODO(you): run verification_test.rb inside sandbox; map exit status → Result
        raise NotImplementedError, "#{self.class}##{__method__}"
      end
    end
  end
end
