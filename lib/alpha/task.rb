# frozen_string_literal: true

module Alpha
  # One atomic graded unit (instruction + sandbox recipe + graders).
  # Seed data lives under scenarios/<name>/tasks/<task>/ (see scenarios/qwen36-daily).
  #
  # Relearning tip: this is a PORO (Plain Old Ruby Object), not ActiveRecord.
  # Prefer loading from YAML/Markdown on disk over putting prompt text in the DB.
  class Task
    attr_reader :name, :kind, :dir

    def self.load(_dir)
      # TODO(you): read task.yml + instruction.md (+ optional invariant.md)
      # Return a Task instance or raise a clear error if the fixture is incomplete.
      raise NotImplementedError, "#{name}.#{__method__} — implement fixture loading"
    end

    def initialize(name:, kind:, dir:)
      @name = name
      @kind = kind
      @dir = dir
    end

    def instruction
      # TODO(you): return instruction.md contents
      raise NotImplementedError, "#{self.class}##{__method__}"
    end

    def prompt(_profile)
      # TODO(you): assemble prompt for shipping vs measurement profiles
      raise NotImplementedError, "#{self.class}##{__method__}"
    end
  end
end
