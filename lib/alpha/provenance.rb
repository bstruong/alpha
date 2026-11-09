# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rbconfig"
require "time"

module Alpha
  # Collects immutable identity for a graded (or local diagnostic) run.
  # Extends existing report/qualification schemas rather than inventing a parallel system.
  module Provenance
    SCHEMA = "alpha.provenance.v1"
    MOVING_REFS = %w[main master latest HEAD].freeze
    SHA_RE = /\A[0-9a-f]{40}\z/i
    DIGEST_RE = %r{\A(?:[a-z0-9._/-]+@)?sha256:[0-9a-f]{64}\z}i

    module_function

    def collect(run_id:, scenario: nil, inference_target: nil, generation_params: nil, seed: nil)
      repos = repository_identities
      content = content_hashes(scenario)
      runtime = runtime_state
      lease = lease_identity
      model = model_identity(inference_target)
      params = generation_params || default_generation_params(seed: seed || scenario&.seed)
      infra = infra_sidecar

      body = {
        "schema" => SCHEMA,
        "run_id" => run_id.to_s,
        "collected_at" => Time.now.utc.iso8601(3),
        "repositories" => repos,
        "runner" => {
          "image" => ENV["ALPHA_RUNNER_IMAGE"],
          "image_digest" => normalize_digest(ENV["ALPHA_RUNNER_IMAGE_DIGEST"] || ENV["ALPHA_RUNNER_IMAGE"]),
          "pod_name" => ENV["POD_NAME"],
          "job_name" => ENV["JOB_NAME"] || ENV["JARVIS_SESSION_RUN_ID"]
        },
        "content" => content,
        "model" => model,
        "jarvis" => jarvis_identity.merge(infra.fetch("jarvis", {})),
        "generation" => params,
        "seeds" => {
          "scenario_seed" => seed || scenario&.seed,
          "executor_seed" => params["seed"]
        },
        "runtime" => runtime,
        "lease" => lease,
        "warmup" => {
          "slot_erase_requested" => true,
          "slot_erase_ok" => infra.dig("warmup", "slot_erase_ok"),
          "health_ok" => infra.dig("warmup", "health_ok")
        },
        "graded_host" => graded_host_context
      }

      body["promotable"] = promotable?(body)
      body["promotable_blockers"] = promotable_blockers(body)
      body
    end

    def promotable?(provenance)
      promotable_blockers(provenance).empty?
    end

    def promotable_blockers(provenance)
      blockers = []
      repos = provenance["repositories"] || {}
      %w[alpha alpha_lab homelab_k3s].each do |key|
        entry = repos[key] || {}
        sha = entry["commit"] || entry["sha"]
        blockers << "#{key}: missing commit SHA" if sha.to_s.empty?
        blockers << "#{key}: dirty worktree" if entry["dirty"] == true
        ref = entry["ref"].to_s
        if MOVING_REFS.include?(ref) && !SHA_RE.match?(sha.to_s)
          blockers << "#{key}: moving ref #{ref.inspect} without pinned SHA"
        end
        blockers << "#{key}: commit is not a full SHA" if sha && !sha.to_s.empty? && !SHA_RE.match?(sha.to_s)
      end

      digest = provenance.dig("runner", "image_digest").to_s
      blockers << "runner: missing image digest" if digest.empty?
      blockers << "runner: image digest is not sha256-pinned" if !digest.empty? && !DIGEST_RE.match?(digest)
      image = provenance.dig("runner", "image").to_s
      blockers << "runner: image uses :latest tag" if image.end_with?(":latest") || image == "latest"

      content = provenance["content"] || {}
      blockers << "content: missing scenario_hash" if content["scenario_hash"].to_s.empty?
      blockers << "content: missing task_hashes" if Array(content["task_hashes"]).empty?

      host = provenance["graded_host"] || {}
      if host["watchtower_job"] != true && ENV["ALPHA_ALLOW_LOCAL_PROMOTE"] != "1"
        blockers << "graded_host: not a Watchtower campaign Job"
      end

      blockers
    end

    def repository_identities
      {
        "alpha" => git_identity(Alpha.config.root, ENV["ALPHA_GIT_REF"], ENV["ALPHA_GIT_SHA"]),
        "alpha_lab" => git_identity(
          ENV["ALPHA_LAB_ROOT"] || File.expand_path("../alpha-lab", Alpha.config.root),
          ENV["ALPHA_LAB_GIT_REF"],
          ENV["ALPHA_LAB_GIT_SHA"]
        ),
        "homelab_k3s" => git_identity(
          ENV["HOMELAB_K3S"] || File.expand_path("../homelab-k3s", Alpha.config.root),
          ENV["HOMELAB_GIT_REF"],
          ENV["HOMELAB_GIT_SHA"]
        )
      }
    end

    def git_identity(path, ref_hint = nil, sha_hint = nil)
      out = {
        "path" => path,
        "ref" => present(ref_hint),
        "commit" => present(sha_hint),
        "dirty" => nil,
        "present" => File.directory?(path)
      }
      return out unless out["present"]

      commit, = capture("git", "-C", path, "rev-parse", "HEAD")
      out["commit"] = present(sha_hint) || present(commit)
      symbolic, = capture("git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD")
      out["ref"] = present(ref_hint) || present(symbolic)
      status, = capture("git", "-C", path, "status", "--porcelain")
      out["dirty"] = !status.to_s.strip.empty?
      out
    rescue StandardError => e
      out["error"] = e.message
      out
    end

    def content_hashes(scenario)
      return { "scenario_hash" => nil, "task_hashes" => [], "grader_hashes" => [], "fixture_hashes" => [] } unless scenario

      task_hashes = Array(scenario.tasks).map do |task|
        {
          "name" => task.name,
          "hash" => hash_paths([
            task.dir,
            File.join(task.dir, "prompt.md"),
            File.join(task.dir, "task.yml"),
            File.join(task.dir, "task.yaml"),
            File.join(task.dir, "verification_test.rb"),
            File.join(task.dir, "solution.patch")
          ])
        }
      end

      grader_paths = [
        File.join(Alpha.config.root, "lib/alpha/grader.rb"),
        File.join(Alpha.config.root, "lib/alpha/grader")
      ]
      fixture_paths = []
      if scenario.dir
        fixture_paths << File.join(scenario.dir, "library")
        fixture_paths << File.join(scenario.dir, "fixtures")
        fixture_paths << File.join(scenario.dir, "held_out")
      end

      {
        "scenario_id" => scenario.id,
        "scenario_dir" => scenario.dir,
        "scenario_hash" => hash_paths([scenario.dir, File.join(scenario.dir.to_s, "scenario.yml"), File.join(scenario.dir.to_s, "scenario.yaml")]),
        "task_hashes" => task_hashes,
        "grader_hashes" => [{ "name" => "alpha/grader", "hash" => hash_paths(grader_paths) }],
        "fixture_hashes" => fixture_paths.select { |p| File.exist?(p) }.map { |p| { "path" => p, "hash" => hash_paths([p]) } }
      }
    end

    def model_identity(inference_target)
      returned = ENV["JARVIS_RETURNED_MODEL_ID"]
      {
        "model_id" => inference_target&.model_id,
        "engine_preset" => inference_target&.engine_preset,
        "base_url_sanitized" => sanitize_url(inference_target&.base_url),
        "model_sha256" => present(ENV["JARVIS_MODEL_SHA256"]),
        "quantization" => present(ENV["JARVIS_MODEL_QUANTIZATION"] || ENV["ALPHA_MODEL_QUANTIZATION"]),
        "returned_model_id" => present(returned)
      }
    end

    def jarvis_identity
      {
        "image_digest" => normalize_digest(ENV["JARVIS_IMAGE_DIGEST"]),
        "config_digest" => present(ENV["JARVIS_CONFIG_DIGEST"]),
        "endpoint_sanitized" => sanitize_url(ENV["OPENAI_BASE_URL"] || ENV["LLAMA_SERVER_URL"])
      }
    end

    def lease_identity
      {
        "holder" => present(ENV["JARVIS_LEASE_HOLDER"] || ENV["JARVIS_SESSION_HOLDER"]),
        "run_id" => present(ENV["JARVIS_SESSION_RUN_ID"] || ENV["JOB_NAME"]),
        "namespace" => present(ENV["JARVIS_K8S_NAMESPACE"] || "jarvis"),
        "lease_name" => present(ENV["JARVIS_LEASE_NAME"] || "jarvis-gpu"),
        "ttl_minutes" => present(ENV["JARVIS_LEASE_MINUTES"])
      }
    end

    def runtime_state
      {
        "ruby" => RUBY_DESCRIPTION,
        "platform" => RbConfig::CONFIG["host_os"],
        "cpu" => cpu_info,
        "gpu" => gpu_info,
        "thermal" => thermal_info,
        "cache" => {
          "llama_slots_erased" => ENV["ALPHA_SLOTS_ERASED"],
          "note" => "cache/slot state recorded at trial start via InferenceTarget#erase_slots!"
        }
      }
    end

    def default_generation_params(seed: 12_345)
      {
        "temperature" => 0.0,
        "seed" => seed,
        "executor_default" => "openai_chat_completions_or_pi"
      }
    end

    def graded_host_context
      watchtower = !ENV["KUBERNETES_SERVICE_HOST"].to_s.empty? &&
                   !ENV["JARVIS_SESSION_RUN_ID"].to_s.empty?
      {
        "watchtower_job" => watchtower,
        "kubernetes" => !ENV["KUBERNETES_SERVICE_HOST"].to_s.empty?,
        "node_class" => Alpha.config.node_class
      }
    end

    def hash_paths(paths)
      digest = Digest::SHA256.new
      Array(paths).compact.sort.each do |path|
        next unless File.exist?(path)

        if File.directory?(path)
          Dir.glob(File.join(path, "**/*"), File::FNM_DOTMATCH).sort.each do |file|
            next unless File.file?(file)
            next if File.basename(file).start_with?(".")

            digest << file.delete_prefix(path.to_s)
            digest << File.binread(file)
          end
        elsif File.file?(path)
          digest << path
          digest << File.binread(path)
        end
      end
      "sha256:#{digest.hexdigest}"
    end

    def hash_file(path)
      return nil unless File.file?(path)

      "sha256:#{Digest::SHA256.file(path).hexdigest}"
    end

    def normalize_digest(value)
      s = value.to_s.strip
      return nil if s.empty?
      return s if DIGEST_RE.match?(s)
      return "sha256:#{s}" if s.match?(/\A[0-9a-f]{64}\z/i)
      if (m = s.match(%r{@(sha256:[0-9a-f]{64})\z}i))
        return m[1]
      end

      nil
    end

    def sanitize_url(url)
      return nil if url.nil? || url.to_s.empty?

      uri = URI.parse(url.to_s)
      host = uri.host.to_s
      # Strip private topology from published provenance; keep scheme + service DNS shape.
      if host.match?(/\A(\d+\.){3}\d+\z/) || host.end_with?(".local") || host.include?("tailscale")
        "#{uri.scheme}://redacted.invalid#{uri.path}"
      else
        "#{uri.scheme}://#{host}#{uri.path}"
      end
    rescue URI::InvalidURIError
      "redacted"
    end

    def present(value)
      s = value.to_s.strip
      s.empty? ? nil : s
    end

    def capture(*cmd)
      out, status = Open3.capture2(*cmd)
      return [nil, status] unless status.success?

      [out.strip, status]
    rescue StandardError
      [nil, nil]
    end

    def cpu_info
      governor = begin
        File.read("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor").strip
      rescue StandardError
        nil
      end
      model = begin
        File.readlines("/proc/cpuinfo").find { |l| l.start_with?("model name") }&.split(":", 2)&.last&.strip
      rescue StandardError
        nil
      end
      { "model" => model, "governor" => governor }
    end

    def gpu_info
      nvidia, = capture("nvidia-smi", "--query-gpu=name,driver_version,uuid,temperature.gpu,power.draw", "--format=csv,noheader")
      return { "nvidia_smi" => nvidia } if nvidia

      { "nvidia_smi" => nil }
    end

    def thermal_info
      zones = Dir.glob("/sys/class/thermal/thermal_zone*/temp").first(4).map do |path|
        { "path" => path, "milli_c" => File.read(path).strip.to_i }
      rescue StandardError
        nil
      end.compact
      { "zones" => zones }
    end

    def infra_sidecar
      path = ENV["ALPHA_INFRA_PROVENANCE_PATH"]
      path ||= begin
        candidates = [
          File.join(Alpha.config.results_dir, "infra_provenance.json"),
          "/data/artifacts/results/infra_provenance.json"
        ]
        candidates.find { |p| File.file?(p) }
      end
      return {} unless path && File.file?(path)

      JSON.parse(File.read(path))
    rescue StandardError
      {}
    end
  end
end
