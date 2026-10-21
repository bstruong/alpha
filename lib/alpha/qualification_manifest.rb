# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module Alpha
  class QualificationManifest
    PRIMARY_RECOMMENDATIONS = {
      "coder" => "qwen36-coder-hybrid",
      "triager" => "gemma4-4b",
      "sanitizer" => "qwen25-coder-14b",
      "extractor" => "qwen25-coder-14b"
    }.freeze

    def self.qualifications_dir
      File.expand_path("../../qualifications", __dir__)
    end

    def self.load_all(dir = qualifications_dir)
      Dir.glob(File.join(dir, "*.json")).reject { |p| p.end_with?("manifest.json") }.map do |path|
        data = JSON.parse(File.read(path))
        next unless data["schema"] == "omega.qualification.v1"

        data["_file"] = File.basename(path)
        data
      end.compact
    end

    def self.active(dir = qualifications_dir)
      now = Time.now.utc
      load_all(dir).select do |q|
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
          "scenario_id" => q["scenario_id"],
          "report_uri" => q["report_uri"],
          "qualified_at" => q["qualified_at"],
          "expires_at" => q["expires_at"],
          "artifact_file" => q["_file"]
        }
      end

      manifest = {
        "schema" => "omega.qualification_manifest.v1",
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
        copied << File.basename(dest)
      end
      copied
    end
  end
end
