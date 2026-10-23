# frozen_string_literal: true

module Alpha
  # Deterministic oracles only — never “ask the model if it passed.”
  module Grader
    Result = Data.define(:name, :pass, :detail)

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
      when "rspec", "rspec_suite"
        RSpecSuite.new
      when "ast_deny", "ast"
        AstDeny.new
      else
        MinitestFile.new
      end
    end
  end
end

require_relative "grader/base"
require_relative "grader/minitest_file"
require_relative "grader/pattern_deny"
require_relative "grader/json_schema"
require_relative "grader/rspec_suite"
require_relative "grader/ast_deny"
