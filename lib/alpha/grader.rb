# frozen_string_literal: true

module Alpha
  # Deterministic oracles only — never “ask the model if it passed.”
  module Grader
    Result = Data.define(:name, :pass, :credit, :detail, :checks) do
      def initialize(name:, pass:, detail: {}, credit: nil, checks: [])
        resolved_checks = Array(checks)
        resolved_credit = if credit.nil?
          pass ? 1.0 : 0.0
        else
          credit.to_f
        end
        super(name: name, pass: pass, credit: resolved_credit, detail: detail, checks: resolved_checks)
      end
    end

    @registry = {}

    def self.register(name, klass)
      @registry[name.to_s] = klass
    end

    def self.resolve(type)
      key = type.to_s
      return @registry[key].new if @registry.key?(key)

      case key
      when "pattern_deny", "pii", "regex"
        PatternDeny.new
      when "json_schema", "schema", "ocr"
        JsonSchema.new
      when "ast_deny", "ast"
        AstDeny.new
      else
        MinitestFile.new
      end
    end
  end
end

require_relative "grader/base"
require_relative "grader/money"
require_relative "grader/minitest_file"
require_relative "grader/pattern_deny"
require_relative "grader/json_schema"
require_relative "grader/ast_deny"
