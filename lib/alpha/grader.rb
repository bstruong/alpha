# frozen_string_literal: true

module Alpha
  # Deterministic oracles only — never “ask the model if it passed.”
  module Grader
    Result = Data.define(:name, :pass, :detail)
  end
end
