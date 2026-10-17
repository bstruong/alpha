# frozen_string_literal: true

module Alpha
  # Deterministic oracles only — never “ask the model if it passed.”
  module Grader
    Result = Data.define(:name, :pass, :detail)
  end
end

require_relative "grader/base"
require_relative "grader/minitest_file"
require_relative "grader/pattern_deny"
require_relative "grader/json_schema"
