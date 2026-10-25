# frozen_string_literal: true

require "ripper"

module Alpha
  module Grader
    # Static AST/lexer analysis grader using Ruby stdlib Ripper.
    # Enforces structural mechanism constraints:
    # - denied_constants: forbidden constant tokens (e.g. `Float`)
    # - denied_keywords: forbidden Ruby keywords (e.g. `rescue` when `Hash#dig` is required)
    # - denied_defs: forbidden explicit `def <name>` definitions (e.g. `has_helmet?` when `method_missing` is required)
    # - required_calls: required method/identifier tokens across source files (e.g. `dig`, `method_missing`)
    # - vacuous Minitest assertions in test files (`assert true, expr` / `assert(true, expr)`)
    class AstDeny < Base
      def self.detect_vacuous_asserts(root_path)
        violations = []
        test_files = Dir.glob(File.join(root_path, "{test,spec}", "**", "*.rb")).sort
        test_files.each do |file_path|
          rel = file_path.sub("#{root_path}/", "")
          tokens = meaningful_tokens(File.read(file_path))
          tokens.each_with_index do |tok, idx|
            next unless tok[:type] == :on_ident && tok[:token] == "assert"

            nxt = tokens[idx + 1]
            after = tokens[idx + 2]
            if nxt && nxt[:type] == :on_kw && nxt[:token] == "true" && after && after[:type] == :on_comma
              violations << {
                file: rel,
                line: tok[:line],
                col: tok[:col],
                token: "assert true,",
                reason: "Vacuous Minitest assertion `assert true, expr` (second arg is failure message)"
              }
            elsif nxt && nxt[:type] == :on_lparen
              arg1 = tokens[idx + 2]
              comma = tokens[idx + 3]
              if arg1 && arg1[:type] == :on_kw && arg1[:token] == "true" && comma && comma[:type] == :on_comma
                violations << {
                  file: rel,
                  line: tok[:line],
                  col: tok[:col],
                  token: "assert(true,",
                  reason: "Vacuous Minitest assertion `assert(true, expr)` (second arg is failure message)"
                }
              end
            end
          end
        end
        violations
      end

      def self.meaningful_tokens(content)
        raw = Ripper.lex(content) || []
        raw.each_with_object([]) do |((lineno, col), type, token, _state), acc|
          next if %i[on_sp on_ignored_nl on_nl on_comment].include?(type)

          acc << { line: lineno, col: col, type: type, token: token }
        end
      end

      def call(sandbox:, task:, check_stability: false) # rubocop:disable Lint/UnusedMethodArgument
        denied_consts = task.respond_to?(:denied_constants) ? Array(task.denied_constants).map(&:to_s) : []
        denied_consts << "Float" if task.respond_to?(:deny_float?) && task.deny_float?
        denied_kws = task.respond_to?(:denied_keywords) ? Array(task.denied_keywords).map(&:to_s) : []
        denied_defs = task.respond_to?(:denied_defs) ? Array(task.denied_defs).map(&:to_s) : []
        required_calls = task.respond_to?(:required_calls) ? Array(task.required_calls).map(&:to_s) : []

        if denied_consts.empty? && denied_kws.empty? && denied_defs.empty? && required_calls.empty?
          denied_consts << "Float" # Default SpecTrap protection against Float arithmetic
        end

        violations = []
        seen_identifiers = []
        files = Dir.glob(File.join(sandbox.path, "**", "*.rb")).reject do |p|
          rel = p.sub("#{sandbox.path}/", "")
          rel.start_with?("test/", "spec/", "tmp/", "vendor/")
        end

        files.each do |file_path|
          rel = file_path.sub("#{sandbox.path}/", "")
          content = File.read(file_path)
          tokens = self.class.meaningful_tokens(content)

          tokens.each_with_index do |tok, idx|
            if tok[:type] == :on_const && denied_consts.include?(tok[:token])
              violations << {
                file: rel,
                line: tok[:line],
                col: tok[:col],
                token: tok[:token],
                reason: "Denied constant #{tok[:token]} found"
              }
            elsif tok[:type] == :on_kw && denied_kws.include?(tok[:token])
              violations << {
                file: rel,
                line: tok[:line],
                col: tok[:col],
                token: tok[:token],
                reason: "Denied keyword #{tok[:token]} found"
              }
            elsif tok[:type] == :on_kw && tok[:token] == "def" && denied_defs.any?
              def_name = extract_def_name(tokens, idx)
              if def_name && denied_defs.include?(def_name)
                violations << {
                  file: rel,
                  line: tok[:line],
                  col: tok[:col],
                  token: def_name,
                  reason: "Denied method definition `def #{def_name}` found"
                }
              end
            end

            seen_identifiers << tok[:token] if %i[on_ident on_kw on_const].include?(tok[:type])
          end
        end

        missing_calls = required_calls - seen_identifiers.uniq
        missing_calls.each do |call_name|
          violations << {
            file: "(sandbox)",
            line: 1,
            col: 0,
            token: call_name,
            reason: "Required call/mechanism `#{call_name}` was not used"
          }
        end

        violations.concat(self.class.detect_vacuous_asserts(sandbox.path))

        passed = violations.empty?
        Result.new(
          name: "AstDeny",
          pass: passed,
          detail: {
            violations: violations,
            missing_calls: missing_calls,
            files_scanned: files.size
          }
        )
      end

      private
        def extract_def_name(tokens, def_idx)
          first = tokens[def_idx + 1]
          return nil unless first

          # Handle `def self.foo` vs `def foo`
          if first[:type] == :on_kw && first[:token] == "self" &&
             tokens[def_idx + 2]&.dig(:type) == :on_period &&
             tokens[def_idx + 3]
            tokens[def_idx + 3][:token]
          else
            first[:token]
          end
        end
    end
  end
end
