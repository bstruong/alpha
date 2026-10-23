# frozen_string_literal: true

require "yaml"

module Alpha
  # One atomic graded unit (instruction + sandbox recipe + graders).
  # Seed data lives under scenarios/<name>/tasks/<task>/ (see scenarios/qwen36-daily).
  class Task
    attr_reader :name, :kind, :dir, :expected_seed, :anchor,
                :restore, :restore_except, :stable_except,
                :denied_patterns, :required_markers, :required_json_keys,
                :expected_json_values, :required_json_markers, :denied_json_patterns, :nested_json_keys,
                :executor_type, :grader_type, :system_prompt, :max_tool_calls
    attr_accessor :thinking, :repair_feedback

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
        stable_except: Array(data["stable_except"]),
        thinking: data["thinking"] || data["thinking_level"],
        denied_patterns: data["denied_patterns"] || {},
        required_markers: Array(data["required_markers"]),
        required_json_keys: Array(data["required_json_keys"]),
        expected_json_values: data["expected_json_values"] || {},
        required_json_markers: Array(data["required_json_markers"]),
        denied_json_patterns: data["denied_json_patterns"] || {},
        nested_json_keys: data["nested_json_keys"] || {},
        executor_type: data["executor"],
        grader_type: data["grader"],
        system_prompt: data["system_prompt"],
        json_mode: data["json_mode"] == true,
        max_tool_calls: data["max_tool_calls"] ? data["max_tool_calls"].to_i : nil
      )
    end

    def initialize(name:, kind:, dir:, expected_seed: 0, anchor: nil,
                   restore: [], restore_except: [], stable_except: [], thinking: nil, repair_feedback: nil,
                   denied_patterns: {}, required_markers: [], required_json_keys: [],
                   expected_json_values: {}, required_json_markers: [], denied_json_patterns: {}, nested_json_keys: {},
                   executor_type: nil, grader_type: nil, system_prompt: nil, json_mode: false,
                   max_tool_calls: nil)
      @name = name
      @kind = kind
      @dir = dir
      @expected_seed = expected_seed
      @anchor = anchor
      @restore = restore
      @restore_except = restore_except
      @stable_except = stable_except
      @thinking = thinking
      @repair_feedback = repair_feedback
      @denied_patterns = denied_patterns
      @required_markers = required_markers
      @required_json_keys = required_json_keys
      @expected_json_values = expected_json_values
      @required_json_markers = required_json_markers
      @denied_json_patterns = denied_json_patterns
      @nested_json_keys = nested_json_keys
      @executor_type = executor_type
      @grader_type = grader_type
      @system_prompt = system_prompt
      @json_mode = json_mode
      @max_tool_calls = max_tool_calls
    end

    def json_mode?
      @json_mode == true
    end

    def with_repair_feedback(feedback)
      copy = dup
      copy.repair_feedback = feedback
      copy
    end

    def with_thinking(level)
      copy = dup
      copy.thinking = level
      copy
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
      unless executor_type.to_s == "openai_chat_completions"
        parts << <<~NOTE.strip
          The Rails application in the current directory is the code to change.
          Leave bin/rails test green.
        NOTE
      end

      if repair_feedback && !repair_feedback.strip.empty?
        parts << <<~REPAIR.strip
          ### Test Failure from Previous Attempt
          #{repair_feedback.strip}

          Please inspect the errors above, fix the issues in the application code, and make sure all tests pass.
        REPAIR
      end

      parts.join("\n\n")
    end

    private
      def present_file(path)
        File.file?(path) && File.size(path).positive? ? path : nil
      end
  end
end
