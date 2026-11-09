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
                :denied_constants, :denied_keywords, :denied_defs, :required_calls,
                :verify_test_fails_on_seed,
                :executor_type, :grader_type, :system_prompt, :max_tool_calls,
                :latency_budget_ms, :workflow_tier,
                :skill, :rung, :scaffold, :role, :wall_seconds,
                :optional_json_markers, :optional_checks, :money_keys, :recon
    attr_accessor :thinking

    def self.load(dir)
      path = File.join(dir, "task.yml")
      raise ArgumentError, "Missing task.yml in #{dir}" unless File.file?(path)

      data = YAML.safe_load_file(path) || {}
      instruction_file = File.join(dir, "instruction.md")
      raise ArgumentError, "Missing instruction.md in #{dir}" unless File.file?(instruction_file)

      anchor_val = data["anchor"].to_s
      rung_val = data["rung"] ? Alpha::Rung.normalize(data["rung"]) : nil
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
        denied_constants: Array(data["denied_constants"]),
        denied_keywords: Array(data["denied_keywords"]),
        denied_defs: Array(data["denied_defs"]),
        required_calls: Array(data["required_calls"]),
        verify_test_fails_on_seed: data["verify_test_fails_on_seed"] == true,
        executor_type: data["executor"],
        grader_type: data["grader"],
        system_prompt: data["system_prompt"],
        json_mode: data["json_mode"] == true,
        max_tool_calls: data["max_tool_calls"] ? data["max_tool_calls"].to_i : nil,
        latency_budget_ms: data["latency_budget_ms"] ? data["latency_budget_ms"].to_i : nil,
        workflow_tier: data["workflow_tier"],
        skill: data["skill"]&.to_s,
        rung: rung_val,
        scaffold: data["scaffold"]&.to_s,
        role: data["role"]&.to_s,
        wall_seconds: data["wall_seconds"] ? data["wall_seconds"].to_i : nil,
        optional_json_markers: Array(data["optional_json_markers"]),
        optional_checks: Array(data["optional_checks"]),
        money_keys: Array(data["money_keys"]),
        recon: data["recon"]
      )
    end

    def initialize(name:, kind:, dir:, expected_seed: 0, anchor: nil,
                   restore: [], restore_except: [], stable_except: [], thinking: nil,
                   denied_patterns: {}, required_markers: [], required_json_keys: [],
                   expected_json_values: {}, required_json_markers: [], denied_json_patterns: {}, nested_json_keys: {},
                   denied_constants: [], denied_keywords: [], denied_defs: [], required_calls: [],
                   verify_test_fails_on_seed: false,
                   executor_type: nil, grader_type: nil, system_prompt: nil, json_mode: false,
                   max_tool_calls: nil, latency_budget_ms: nil, workflow_tier: nil,
                   skill: nil, rung: nil, scaffold: nil, role: nil, wall_seconds: nil,
                   optional_json_markers: [], optional_checks: [], money_keys: [], recon: nil)
      @name = name
      @kind = kind
      @dir = dir
      @expected_seed = expected_seed
      @anchor = anchor
      @restore = restore
      @restore_except = restore_except
      @stable_except = stable_except
      @thinking = thinking
      @denied_patterns = denied_patterns
      @required_markers = required_markers
      @required_json_keys = required_json_keys
      @expected_json_values = expected_json_values
      @required_json_markers = required_json_markers
      @denied_json_patterns = denied_json_patterns
      @nested_json_keys = nested_json_keys
      @denied_constants = denied_constants
      @denied_keywords = denied_keywords
      @denied_defs = denied_defs
      @required_calls = required_calls
      @verify_test_fails_on_seed = verify_test_fails_on_seed
      @executor_type = executor_type
      @grader_type = grader_type
      @system_prompt = system_prompt
      @json_mode = json_mode
      @max_tool_calls = max_tool_calls
      @latency_budget_ms = latency_budget_ms
      @workflow_tier = workflow_tier&.to_s
      @skill = skill
      @rung = rung
      @scaffold = scaffold
      @role = role
      @wall_seconds = wall_seconds
      @optional_json_markers = optional_json_markers
      @optional_checks = optional_checks
      @money_keys = money_keys
      @recon = recon
    end

    def verify_test_fails_on_seed?
      @verify_test_fails_on_seed == true
    end

    def json_mode?
      @json_mode == true
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
      use_invariant = self.class.resolve_include_invariant(profile, include_invariant)

      parts = [ instruction.strip ]
      parts << invariant.strip if use_invariant && invariant
      unless executor_type.to_s == "openai_chat_completions"
        parts << <<~NOTE.strip
          The Rails application in the current directory is the code to change.
          Leave bin/rails test green.
        NOTE
      end

      parts.join("\n\n")
    end

    # Answer-bearing invariant.md is reserved for oracle/debug (or an explicit
    # Profile#include_invariant). Evaluated shipping/measurement must opt in via
    # the Profile object from scenario.yml — string "shipping" alone does not
    # inject invariants (Phase 3).
    def self.resolve_include_invariant(profile, override = nil)
      return override unless override.nil?
      return profile.include_invariant if profile.respond_to?(:include_invariant)

      case profile.to_s
      when "oracle", "debug" then true
      else false
      end
    end

    private
      def present_file(path)
        File.file?(path) && File.size(path).positive? ? path : nil
      end
  end
end
