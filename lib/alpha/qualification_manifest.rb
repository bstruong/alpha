# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module Alpha
  class QualificationManifest
    # Historical primary recommendations for manifest generation. These are not
    # routing authority; Phase 0 archived Own/Unattended routes remain disabled.
    PRIMARY_RECOMMENDATIONS = {
      "coder" => "qwen36-coder-hybrid",
      "scoped_coder" => "qwen36-coder-hybrid",
      "ruby_coder" => "glm47-reap",
      "frontend_coder" => "glm47-reap",
      "hotwire_coder" => "glm47-reap",
      "triager" => "qwen36-coder-hybrid",
      "sanitizer" => "gemma4-4b",
      "extractor" => "qwen36-coder-hybrid",
      "crm_ops" => "gemma4-12b",
      "vault_extractor" => "glm47-reap",
      "vault_sanitizer" => "qwen36-coder-hybrid",
      "recon_ops" => "glm47-reap",
      "ledger_coder" => "glm47-reap"
    }.freeze

    SCHEMA = "alpha.qualification.v2"
    MANIFEST_SCHEMA = "alpha.qualification_manifest.v2"

    def self.qualifications_dir
      Alpha.config.qualifications_dir
    end

    def self.load_all(dir = qualifications_dir)
      Dir.glob(File.join(dir, "*.json")).reject { |p| p.end_with?("manifest.json") }.map do |path|
        data = JSON.parse(File.read(path))
        next unless data["schema"] == SCHEMA

        data["_file"] = File.basename(path)
        data
      end.compact
    end

    def self.active(dir = qualifications_dir)
      now = Time.now.utc
      load_all(dir).select do |q|
        next false if q.key?("qualified") && q["qualified"] != true

        exp = Time.parse(q["expires_at"]) rescue nil
        exp && exp > now
      end
    end

    def self.generate(dir = qualifications_dir)
      items = active(dir)
      by_role = {}

      items.sort_by { |q| [ q["role"].to_s, -q["pass_at_1"].to_f ] }.each do |q|
        role = q["role"] || "unknown"
        by_role[role] ||= {
          "primary_model" => PRIMARY_RECOMMENDATIONS[role] || q["model_id"],
          "qualified_models" => []
        }
        by_role[role]["qualified_models"] << {
          "model_id" => q["model_id"],
          "engine_preset" => q["engine_preset"],
          "prompt_preset" => q["prompt_preset"],
          "pass_at_1" => q["pass_at_1"],
          "max_rung" => q["max_rung"],
          "ceiling_rung" => q["ceiling_rung"],
          "credit_mean" => q["credit_mean"],
          "ship_skills" => q["ship_skills"],
          "scenario_id" => q["scenario_id"],
          "report_uri" => q["report_uri"],
          "qualified_at" => q["qualified_at"],
          "expires_at" => q["expires_at"],
          "artifact_file" => q["_file"]
        }
      end

      manifest = {
        "schema" => MANIFEST_SCHEMA,
        "generated_at" => Time.now.utc.iso8601,
        "roles" => by_role
      }

      manifest_path = File.join(dir, "manifest.json")
      File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
      manifest
    end

    def self.export(target_dir, source_dir = qualifications_dir)
      FileUtils.mkdir_p(target_dir)
      generate(source_dir)

      copied = []
      Dir.glob(File.join(source_dir, "*.json")).each do |src|
        dest = File.join(target_dir, File.basename(src))
        FileUtils.cp(src, dest)
        copied << File.basename(src)
      end
      copied
    end
  end
end
