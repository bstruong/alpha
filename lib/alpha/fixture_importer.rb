# frozen_string_literal: true

require "fileutils"
require "json"
require "yaml"

module Alpha
  # Ingests an Omega failure export (omega.failure_export.v1) into a draft
  # Alpha regression task under scenarios/omega_regressions/tasks/<slug>/.
  # Enforces mandatory PII/secret scrubbing and the human/frontier grader gate.
  # See docs/shape-up/03-alpha-omega-contract.md §3.
  class FixtureImporter
    SECRET_PATTERNS = [
      /(?:api[_-]?key|secret|token|password|bearer\s+[a-z0-9_\-\.]+)\s*[:=]\s*['"]?[a-z0-9_\-\.]{8,}['"]?/i,
      /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
      /\b\d{3}-\d{2}-\d{4}\b/ # SSN
    ].freeze

    def self.import(export_path, destination_dir: nil)
      new.import(export_path, destination_dir: destination_dir)
    end

    def import(export_path, destination_dir: nil)
      raise ArgumentError, "File not found: #{export_path}" unless File.file?(export_path)

      data = JSON.parse(File.read(export_path))
      unless data["schema"] == "omega.failure_export.v1"
        raise ArgumentError, "Unsupported export schema: #{data["schema"].inspect} (expected omega.failure_export.v1)"
      end

      session_id = data.fetch("omega_session_id")
      slug = "regression-#{session_id[0..7]}"
      scenario_dir = destination_dir || File.join(Alpha.config.scenarios_dir, "omega_regressions")
      tasks_dir = File.join(scenario_dir, "tasks")
      task_dir = File.join(tasks_dir, slug)

      FileUtils.mkdir_p(task_dir)

      # 1. Build and sanitize instruction markdown
      instruction_content = build_instruction(data)
      File.write(File.join(task_dir, "instruction.md"), instruction_content)

      # 2. Write task.yml metadata
      task_meta = {
        "name" => slug,
        "kind" => "graded",
        "origin" => "omega",
        "omega_session_id" => session_id,
        "failed_model" => data["model_id"],
        "prompt_preset" => data["prompt_preset"],
        "exit_reason" => data["exit_reason"],
        "status" => "draft_needs_grader",
        "expected_seed" => 0,
        "repo_fingerprint" => data["repo_fingerprint"]
      }
      File.write(File.join(task_dir, "task.yml"), YAML.dump(task_meta))

      # 3. Ensure omega_regressions scenario.yml exists
      ensure_scenario_manifest(scenario_dir, slug)

      {
        slug: slug,
        task_dir: task_dir,
        status: "draft_needs_grader"
      }
    end

    private
      def build_instruction(data)
        sections = []
        sections << "# Task: Replicate & Fix Failure from Omega Session #{data["omega_session_id"][0..7]}"
        sections << ""
        sections << "## Initial Request"
        sections << sanitize(data["initial_prompt"].to_s.strip)

        follow_ups = Array(data["follow_ups"]).reject(&:empty?)
        if follow_ups.any?
          sections << ""
          sections << "## Operator Follow-ups"
          follow_ups.each_with_index do |fu, idx|
            sections << "#{idx + 1}. #{sanitize(fu.to_s.strip)}"
          end
        end

        steers = Array(data["steers"]).reject(&:empty?)
        if steers.any?
          sections << ""
          sections << "## Mid-Flight Operator Steers"
          steers.each_with_index do |st, idx|
            sections << "#{idx + 1}. #{sanitize(st.to_s.strip)}"
          end
        end

        if data["operator_notes"] && !data["operator_notes"].to_s.strip.empty?
          sections << ""
          sections << "## Operator Notes"
          sections << sanitize(data["operator_notes"].to_s.strip)
        end

        sections.join("\n") + "\n"
      end

      def sanitize(text)
        cleaned = text.dup
        SECRET_PATTERNS.each do |pat|
          cleaned.gsub!(pat, "[REDACTED]")
        end
        cleaned
      end

      def ensure_scenario_manifest(scenario_dir, new_slug)
        manifest_path = File.join(scenario_dir, "scenario.yml")
        manifest = File.file?(manifest_path) ? (YAML.safe_load_file(manifest_path) || {}) : {}

        manifest["id"] ||= "omega_regressions"
        manifest["description"] ||= "Regression tasks extracted from failed Omega production sessions."
        manifest["tasks"] ||= []
        manifest["tasks"] << new_slug unless manifest["tasks"].include?(new_slug)

        File.write(manifest_path, YAML.dump(manifest))
      end
  end
end
