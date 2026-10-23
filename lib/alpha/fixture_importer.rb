# frozen_string_literal: true

require "fileutils"
require "json"
require "yaml"

module Alpha
  # Ingests failure sessions into draft Alpha regression tasks under
  # scenarios/<scenario>/tasks/<slug>/.
  # Supports:
  #   1. Omega failure exports (omega.failure_export.v1)
  #   2. Native Pi session transcripts (*.jsonl from ~/.pi/agent/sessions/)
  # Enforces mandatory PII/secret scrubbing and the human/frontier grader gate.
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

      raw = File.read(export_path)
      first_line = raw.lines.first.to_s.strip

      if export_path.end_with?(".jsonl") || first_line.start_with?('{"type":"session"')
        import_pi_session(raw, export_path, destination_dir: destination_dir)
      else
        import_omega_export(raw, destination_dir: destination_dir)
      end
    end

    private
      def import_omega_export(raw, destination_dir: nil)
        data = JSON.parse(raw)
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
        instruction_content = build_omega_instruction(data)
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

        # 3. Ensure scenario.yml exists
        ensure_scenario_manifest(scenario_dir, slug, id: "omega_regressions", description: "Regression tasks extracted from failed Omega production sessions.")

        {
          slug: slug,
          task_dir: task_dir,
          status: "draft_needs_grader",
          origin: "omega"
        }
      end

      def import_pi_session(raw, export_path, destination_dir: nil)
        events = raw.each_line.map do |line|
          line = line.strip
          next if line.empty?
          JSON.parse(line) rescue nil
        end.compact

        session_event = events.find { |e| e["type"] == "session" } || {}
        session_id = session_event["id"] || File.basename(export_path, ".*")
        cwd = session_event["cwd"]

        model_event = events.find { |e| e["type"] == "model_change" } || {}
        model_id = model_event["modelId"] || "qwen36-coder-hybrid"

        # Collect user messages
        user_prompts = []
        events.each do |e|
          next unless e["type"] == "message" && e.dig("message", "role") == "user"
          content = e.dig("message", "content")
          text = if content.is_a?(Array)
            content.map do |item|
              if item.is_a?(Hash)
                item["text"] || item["content"]
              else
                item.to_s
              end
            end.compact.join("\n").strip
          else
            content.to_s.strip
          end
          user_prompts << text unless text.empty?
        end

        raise ArgumentError, "No user prompts found in Pi session #{export_path}" if user_prompts.empty?

        initial_prompt = user_prompts.first
        follow_ups = user_prompts[1..] || []

        slug = "regression-pi-#{session_id[0..7]}"
        scenario_dir = destination_dir || File.join(Alpha.config.scenarios_dir, "workstation_regressions")
        tasks_dir = File.join(scenario_dir, "tasks")
        task_dir = File.join(tasks_dir, slug)

        FileUtils.mkdir_p(task_dir)

        # 1. Build and sanitize instruction markdown
        instruction_content = build_pi_instruction(session_id, initial_prompt, follow_ups, cwd)
        File.write(File.join(task_dir, "instruction.md"), instruction_content)

        # 2. Write task.yml metadata
        task_meta = {
          "name" => slug,
          "kind" => "graded",
          "origin" => "pi_session",
          "session_id" => session_id,
          "failed_model" => model_id,
          "cwd" => cwd,
          "status" => "draft_needs_grader",
          "expected_seed" => 0
        }
        File.write(File.join(task_dir, "task.yml"), YAML.dump(task_meta))

        # 3. Ensure scenario.yml manifest exists
        ensure_scenario_manifest(scenario_dir, slug, id: "workstation_regressions", description: "Regression tasks extracted from local workstation Pi coding agent sessions.")

        {
          slug: slug,
          task_dir: task_dir,
          status: "draft_needs_grader",
          origin: "pi_session"
        }
      end

      def build_omega_instruction(data)
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

      def build_pi_instruction(session_id, initial_prompt, follow_ups, cwd)
        sections = []
        sections << "# Task: Replicate & Fix Failure from Pi Session #{session_id[0..7]}"
        sections << ""
        sections << "## Working Directory"
        sections << (cwd ? "`#{cwd}`" : "Default workspace")
        sections << ""
        sections << "## Initial Request"
        sections << sanitize(initial_prompt)

        if follow_ups.any?
          sections << ""
          sections << "## Operator Follow-ups"
          follow_ups.each_with_index do |fu, idx|
            sections << "#{idx + 1}. #{sanitize(fu)}"
          end
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

      def ensure_scenario_manifest(scenario_dir, new_slug, id: "omega_regressions", description: "Regression tasks extracted from failed Omega production sessions.")
        manifest_path = File.join(scenario_dir, "scenario.yml")
        manifest = File.file?(manifest_path) ? (YAML.safe_load_file(manifest_path) || {}) : {}

        manifest["id"] ||= id
        manifest["description"] ||= description
        manifest["tasks"] ||= []
        manifest["tasks"] << new_slug unless manifest["tasks"].include?(new_slug)

        File.write(manifest_path, YAML.dump(manifest))
      end
  end
end
