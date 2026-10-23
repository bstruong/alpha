# frozen_string_literal: true

require "ripper"

module Alpha
  module Grader
    # Static AST analysis grader using Ruby stdlib Ripper lexer.
    # Forbids specific constant identifiers (e.g. `Float`), calls, or token patterns
    # in modified or target Ruby source files.
    class AstDeny < Base
      def call(sandbox:, task:, check_stability: false)
        denied_consts = task.respond_to?(:denied_constants) ? Array(task.denied_constants).map(&:to_s) : []
        denied_consts << "Float" if task.respond_to?(:deny_float?) && task.deny_float?
        denied_consts << "Float" if denied_consts.empty? # Default SpecTrap protection against Float arithmetic

        violations = []
        files = Dir.glob(File.join(sandbox.path, "**", "*.rb")).reject do |p|
          rel = p.sub("#{sandbox.path}/", "")
          rel.start_with?("test/", "spec/", "tmp/", "vendor/")
        end

        files.each do |file_path|
          content = File.read(file_path)
          tokens = Ripper.lex(content)
          tokens.each do |(lineno, col), type, token, _state|
            if type == :on_const && denied_consts.include?(token)
              violations << {
                file: file_path.sub("#{sandbox.path}/", ""),
                line: lineno,
                col: col,
                token: token,
                reason: "Denied constant #{token} found"
              }
            end
          end
        end

        passed = violations.empty?
        Result.new(
          name: "AstDeny",
          pass: passed,
          detail: { violations: violations, files_scanned: files.size }
        )
      end
    end
  end
end
