# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Alpha
  # One machine-readable evidence index for a single campaign/run.
  # Created at start and finalized in-place at completion (same file).
  class RunManifest
    SCHEMA = "alpha.run_manifest.v1"
    FILENAME = "run_manifest.json"

    def self.path_for(run_id, results_dir: Alpha.config.results_dir)
      File.join(results_dir, "runs", run_id.to_s, FILENAME)
    end

    def self.create!(run_id, scenario: nil, inference_target: nil, generation_params: nil, seed: nil,
                     results_dir: Alpha.config.results_dir)
      dir = File.join(results_dir, "runs", run_id.to_s)
      FileUtils.mkdir_p(dir)
      path = path_for(run_id, results_dir: results_dir)

      provenance = Provenance.collect(
        run_id: run_id,
        scenario: scenario,
        inference_target: inference_target,
        generation_params: generation_params,
        seed: seed || scenario&.seed
      )

      payload = {
        "schema" => SCHEMA,
        "run_id" => run_id.to_s,
        "status" => "started",
        "started_at" => Time.now.utc.iso8601(3),
        "finished_at" => nil,
        "terminal_status" => nil,
        "promotable" => provenance["promotable"] == true,
        "promotable_blockers" => provenance["promotable_blockers"] || [],
        "provenance" => provenance,
        "trials" => [],
        "artifacts" => {
          "summary_json" => nil,
          "report_md" => nil,
          "raw_root" => File.join("results", "runs", run_id.to_s)
        },
        "artifact_hashes" => {}
      }

      atomic_write!(path, payload)
      payload
    end

    def self.load(run_id, results_dir: Alpha.config.results_dir)
      path = path_for(run_id, results_dir: results_dir)
      return nil unless File.file?(path)

      JSON.parse(File.read(path))
    end

    def self.record_trial!(run_id, trial:, results_dir: Alpha.config.results_dir)
      path = path_for(run_id, results_dir: results_dir)
      payload = load(run_id, results_dir: results_dir) || create!(run_id, results_dir: results_dir)
      entry = {
        "trial_id" => trial[:trial_id] || trial["trial_id"],
        "task_name" => trial[:task_name] || trial["task_name"],
        "trial" => trial[:trial] || trial["trial"],
        "seed" => trial[:seed] || trial["seed"],
        "result_json" => relative_result_path(run_id, trial)
      }
      payload["trials"] = Array(payload["trials"])
      payload["trials"] << entry unless payload["trials"].any? { |t| t["trial_id"] == entry["trial_id"] }
      atomic_write!(path, payload)
      payload
    end

    def self.finalize!(run_id, terminal_status:, summary_path: nil, report_path: nil, summary_payload: nil,
                       results_dir: Alpha.config.results_dir)
      path = path_for(run_id, results_dir: results_dir)
      payload = load(run_id, results_dir: results_dir)
      payload ||= create!(run_id, results_dir: results_dir)

      if summary_payload && summary_payload["provenance"]
        # Prefer end-of-run provenance when Report attached a refreshed block.
        payload["provenance"] = summary_payload["provenance"]
        payload["promotable"] = summary_payload.dig("provenance", "promotable") == true
        payload["promotable_blockers"] = summary_payload.dig("provenance", "promotable_blockers") || []
      end

      payload["status"] = "final"
      payload["finished_at"] = Time.now.utc.iso8601(3)
      payload["terminal_status"] = terminal_status.to_s
      payload["artifacts"] ||= {}
      payload["artifacts"]["summary_json"] = summary_path && File.file?(summary_path) ? summary_path : payload.dig("artifacts", "summary_json")
      payload["artifacts"]["report_md"] = report_path && File.file?(report_path) ? report_path : payload.dig("artifacts", "report_md")

      hashes = {}
      {
        "run_manifest" => path,
        "summary_json" => payload.dig("artifacts", "summary_json"),
        "report_md" => payload.dig("artifacts", "report_md")
      }.each do |key, file|
        next unless file && File.file?(file)

        hashes[key] = Provenance.hash_file(file)
      end

      # Hash retained raw trial result.json files (ignored under results/runs/).
      trial_root = File.join(results_dir, "runs", run_id.to_s)
      Dir.glob(File.join(trial_root, "**", "result.json")).sort.each do |file|
        rel = file.delete_prefix("#{results_dir}/")
        hashes[rel] = Provenance.hash_file(file)
      end
      payload["artifact_hashes"] = hashes

      atomic_write!(path, payload)
      payload
    end

    def self.sanitized_bundle(run_id, results_dir: Alpha.config.results_dir)
      payload = load(run_id, results_dir: results_dir)
      return nil unless payload

      bundle = Marshal.load(Marshal.dump(payload))
      # Published bundles must not carry private topology or absolute host paths.
      %w[repositories].each do |key|
        (bundle.dig("provenance", key) || {}).each_value do |repo|
          next unless repo.is_a?(Hash)

          repo.delete("path")
          repo.delete("error")
        end
      end
      if (artifacts = bundle["artifacts"])
        artifacts["summary_json"] = relativize_published(artifacts["summary_json"], run_id)
        artifacts["report_md"] = relativize_published(artifacts["report_md"], run_id)
      end
      bundle
    end

    def self.atomic_write!(path, payload)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.tmp-#{Process.pid}"
      File.write(tmp, JSON.pretty_generate(stable_json(payload)) + "\n")
      File.rename(tmp, path)
    ensure
      FileUtils.rm_f(tmp) if defined?(tmp) && tmp && File.exist?(tmp)
    end
    private_class_method :atomic_write!

    def self.stable_json(value)
      case value
      when Hash
        value.keys.sort.each_with_object({}) { |k, h| h[k] = stable_json(value[k]) }
      when Array
        value.map { |v| stable_json(v) }
      else
        value
      end
    end
    private_class_method :stable_json

    def self.relative_result_path(run_id, trial)
      task = trial[:task_name] || trial["task_name"]
      num = trial[:trial] || trial["trial"] || 1
      File.join("results", "runs", run_id.to_s, task.to_s, "trial-#{num}", "result.json")
    end
    private_class_method :relative_result_path

    def self.relativize_published(path, run_id)
      return path if path.nil?
      return "results/runs/#{run_id}/summary.json" if path.to_s.end_with?("summary.json")
      return "reports/#{run_id}.md" if path.to_s.end_with?("#{run_id}.md")

      path.to_s
    end
    private_class_method :relativize_published
  end
end
