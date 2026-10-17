# frozen_string_literal: true

require "yaml"

module Alpha
  # Ordered list of tasks + budget + default inference target.
  class Scenario
    DEFAULT_ORDER = %w[
      gate-hello gate-boot gate-edit
      empty-card spec-wins library-cache audit-three once-only erase-account
    ].freeze

    Profile = Data.define(:name, :bullet_cap, :include_invariant) do
      def self.fetch(name, config = {})
        profile_cfg = config[name.to_s] || {}
        case name.to_s
        when "shipping"
          new("shipping", profile_cfg.fetch("bullet_cap", true), profile_cfg.fetch("include_invariant", true))
        when "measurement"
          new("measurement", profile_cfg.fetch("bullet_cap", false), profile_cfg.fetch("include_invariant", false))
        else
          raise ArgumentError, "Unknown profile #{name.inspect} (expected shipping or measurement)"
        end
      end
    end

    attr_reader :id, :dir, :tasks, :profile, :seed, :budget, :qualification, :base_app_dir,
                :default_model, :executor_type, :grader_type, :role

    def self.scenarios_root
      File.expand_path("../../scenarios", __dir__)
    end

    def self.load(id, profile: "shipping", only_task: nil)
      scenario_dir = File.join(scenarios_root, id.to_s)
      raise ArgumentError, "Scenario directory not found: #{scenario_dir}" unless File.directory?(scenario_dir)

      manifest_path = File.join(scenario_dir, "scenario.yml")
      manifest = File.file?(manifest_path) ? (YAML.safe_load_file(manifest_path) || {}) : {}

      order = Array(manifest["tasks"]).presence || DEFAULT_ORDER
      tasks_dir = File.join(scenario_dir, "tasks")
      raise ArgumentError, "Tasks directory not found: #{tasks_dir}" unless File.directory?(tasks_dir)

      loaded_tasks = Dir.children(tasks_dir).sort.filter_map do |entry|
        task_dir = File.join(tasks_dir, entry)
        next unless File.file?(File.join(task_dir, "task.yml"))

        Task.load(task_dir)
      end

      loaded_tasks.sort_by! { |t| order.index(t.name) || order.size }
      if only_task
        loaded_tasks.select! { |t| t.name == only_task.to_s }
        raise ArgumentError, "Task #{only_task.inspect} not found in scenario #{id}" if loaded_tasks.empty?
      end

      profile_obj = Profile.fetch(profile, manifest.fetch("profiles", {}))
      base_app = manifest.fetch("base_app", "library")
      base_app_dir = File.expand_path(base_app, scenario_dir)
      budget = {
        wall_seconds: manifest.dig("budget", "wall_seconds") || 720,
        max_tool_calls: manifest.dig("budget", "max_tool_calls") || 40
      }
      qualification = {
        gate_pass_at_1: manifest.dig("qualification", "gate_pass_at_1") || 1.0,
        graded_pass_at_1: manifest.dig("qualification", "graded_pass_at_1") || 0.70
      }

      new(
        id: manifest.fetch("id", id.to_s),
        dir: scenario_dir,
        tasks: loaded_tasks,
        profile: profile_obj,
        seed: manifest.fetch("seed", 12_345),
        budget: budget,
        qualification: qualification,
        base_app_dir: base_app_dir,
        default_model: manifest.fetch("default_model", "qwen36-coder-hybrid"),
        executor_type: manifest["executor"],
        grader_type: manifest["grader"],
        role: manifest.fetch("role", "coder")
      )
    end

    def initialize(id:, tasks:, profile: "shipping", dir: nil, seed: 12_345,
                   budget: {}, qualification: {}, base_app_dir: nil, default_model: "qwen36-coder-hybrid",
                   executor_type: nil, grader_type: nil, role: "coder")
      @id = id
      @dir = dir
      @tasks = tasks
      @profile = profile.is_a?(Profile) ? profile : Profile.fetch(profile)
      @seed = seed
      @budget = budget
      @qualification = qualification
      @base_app_dir = base_app_dir
      @default_model = default_model
      @executor_type = executor_type
      @grader_type = grader_type
      @role = role
    end
  end
end
