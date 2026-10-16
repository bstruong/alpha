# frozen_string_literal: true

require "yaml"

module Alpha
  # One atomic graded unit (instruction + sandbox recipe + graders).
  # Seed data lives under scenarios/<name>/tasks/<task>/ (see scenarios/qwen36-daily).
  class Task
    attr_reader :name, :kind, :dir, :expected_seed, :anchor,
                :restore, :restore_except, :stable_except

    def self.load(dir)
      path = File.join(dir, "task.yml")
      raise ArgumentError, "Missing task.yml in #{dir}" unless File.file?(path)

      data = YAML.safe_load_file(path) || {}
      instruction_file = File.join(dir, "instruction.md")
      raise ArgumentError, "Missing instruction.md in #{dir}" unless File.file?(instruction_file)

      anchor_val = data["anchor"].to_s
      new(
        name: data.fetch("name"),
        kind: data.fetch("kind"),
        dir: dir,
        expected_seed: data.fetch("expected_seed", 0),
        anchor: anchor_val.empty? ? nil : anchor_val,
        restore: Array(data["restore"]),
        restore_except: Array(data["restore_except"]),
        stable_except: Array(data["stable_except"])
      )
    end

    def initialize(name:, kind:, dir:, expected_seed: 0, anchor: nil,
                   restore: [], restore_except: [], stable_except: [])
      @name = name
      @kind = kind
      @dir = dir
      @expected_seed = expected_seed
      @anchor = anchor
      @restore = restore
      @restore_except = restore_except
      @stable_except = stable_except
    end

    def gate?
      kind == "gate"
    end

    def instruction
      File.read(File.join(dir, "instruction.md"))
    end

    def invariant
      path = File.join(dir, "invariant.md")
      File.file?(path) ? File.read(path) : nil
    end

    def environment_patch
      present_file(File.join(dir, "environment.patch"))
    end

    def solution_patch
      present_file(File.join(dir, "solution.patch"))
    end

    def verifier_path
      present_file(File.join(dir, "verification_test.rb"))
    end

    def prompt(profile = "shipping", include_invariant: nil)
      use_invariant = if include_invariant.nil?
        profile.to_s == "shipping"
      else
        include_invariant
      end

      parts = [ instruction.strip ]
      parts << invariant.strip if use_invariant && invariant
      parts << <<~NOTE.strip
        The Rails application in the current directory is the code to change.
        Leave bin/rails test green.
      NOTE
      parts.join("\n\n")
    end

    private
      def present_file(path)
        File.file?(path) && File.size(path).positive? ? path : nil
      end
  end
end
