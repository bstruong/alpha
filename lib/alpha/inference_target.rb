# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Alpha
  # Points at the AM5 homelab (watchtower) OpenAI-compatible endpoint.
  # Standardizes on http://192.168.1.92:8080/v1 by default so invocations
  # work identically from watchtower (AM5) or metrotower (Haswell desk).
  class InferenceTarget
    DEFAULT_HOST_URL = "http://192.168.1.92:8080"
    DEFAULT_DEPLOYMENT = "alpha-llama"
    DEFAULT_NAMESPACE = "alpha"

    attr_reader :base_url, :model_id, :engine_preset, :context_window

    def self.repo_root
      File.expand_path("../..", __dir__)
    end

    def self.from_engine(preset_name)
      ini_path = File.join(repo_root, "engine", "models.ini")
      sections = File.file?(ini_path) ? parse_ini(ini_path) : {}
      global = sections.fetch("*", {})
      section = sections.fetch(preset_name.to_s, {})
      merged = global.merge(section)

      model_id = merged["alias"] || preset_name.to_s
      ctx_size = Integer(merged.fetch("ctx-size", 262_144)) rescue 262_144

      server_url = ENV["OPENAI_API_BASE"] ||
        ENV["OPENAI_BASE_URL"] ||
        (ENV["LLAMA_SERVER_URL"] && "#{ENV["LLAMA_SERVER_URL"].chomp("/")}/v1") ||
        "#{DEFAULT_HOST_URL}/v1"

      new(
        base_url: server_url,
        model_id: model_id,
        engine_preset: preset_name.to_s,
        context_window: ctx_size
      )
    end

    def self.parse_ini(path)
      sections = {}
      current = nil
      File.foreach(path) do |raw_line|
        line = raw_line.strip
        next if line.empty? || line.start_with?(";", "#")

        if (match = line.match(/\A\[(.+)\]\z/))
          current = match[1]
          sections[current] ||= {}
        elsif current && line.include?("=")
          key, val = line.split("=", 2).map(&:strip)
          sections[current][key] = val
        end
      end
      sections
    end

    def self.ssh_host
      ENV["ALPHA_SSH_HOST"] || "watchtower"
    end

    def self.local_kubectl?
      return @local_kubectl unless @local_kubectl.nil?

      @local_kubectl = system("kubectl get deployment -n #{DEFAULT_NAMESPACE} #{DEFAULT_DEPLOYMENT} >/dev/null 2>&1")
    end

    def self.reset_local_kubectl_cache!
      @local_kubectl = nil
    end

    def self.kubectl(args, capture: false)
      cmd = if local_kubectl?
              "kubectl #{args}"
            else
              "ssh #{ssh_host} \"kubectl #{args}\""
            end

      if capture
        `#{cmd}`.strip
      else
        system(cmd)
      end
    end

    def self.preset_args(preset_name)
      case preset_name.to_s
      when "glm47-reap", "glm47"
        [
          "--model", "/models/GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf",
          "--alias", "glm47-reap",
          "--host", "0.0.0.0",
          "--port", "8080",
          "--ctx-size", "131072",
          "--n-gpu-layers", "all",
          "--cpu-moe",
          "--threads", "7",
          "--threads-batch", "7",
          "--parallel", "2",
          "--batch-size", "2048",
          "--ubatch-size", "2048",
          "--flash-attn", "on",
          "--load-mode", "mlock",
          "--cache-type-k", "q8_0",
          "--cache-type-v", "q8_0",
          "--jinja",
          "--metrics",
          "--slots"
        ]
      else # default to qwen36-coder-hybrid
        [
          "--model", "/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf",
          "--alias", "qwen36-coder-hybrid,qwen36-coder",
          "--host", "0.0.0.0",
          "--port", "8080",
          "--ctx-size", "262144",
          "--n-gpu-layers", "all",
          "--n-cpu-moe", "32",
          "--threads", "7",
          "--threads-batch", "7",
          "--parallel", "2",
          "--batch-size", "2048",
          "--ubatch-size", "2048",
          "--flash-attn", "on",
          "--load-mode", "mlock",
          "--cache-type-k", "q8_0",
          "--cache-type-v", "q8_0",
          "--jinja",
          "--metrics",
          "--slots"
        ]
      end
    end

    def self.ensure_preset!(preset_name)
      target_args = preset_args(preset_name)
      current_raw = kubectl("get deployment #{DEFAULT_DEPLOYMENT} -n #{DEFAULT_NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].args}'", capture: true)
      current_args = JSON.parse(current_raw) rescue []

      if current_args != target_args
        puts "Switching #{DEFAULT_DEPLOYMENT} deployment preset to '#{preset_name}'..."
        patch_json = {
          spec: {
            template: {
              spec: {
                containers: [
                  {
                    name: "llama-server",
                    args: target_args
                  }
                ]
              }
            }
          }
        }.to_json
        escaped_patch = patch_json.gsub('"', '\"')
        kubectl("patch deployment #{DEFAULT_DEPLOYMENT} -n #{DEFAULT_NAMESPACE} --type='strategic' -p \"#{escaped_patch}\"")
      end
    end

    def self.engine_up(preset: nil, timeout_s: 30)
      target = from_engine(preset || "qwen36-coder-hybrid")
      ensure_preset!(target.engine_preset) if preset

      if target.healthy?
        puts "Inference engine is already running and healthy (#{target.model_id} at #{target.base_url})."
        return true
      end

      puts "Waking #{DEFAULT_DEPLOYMENT} deployment (scaling to 1 replica)..."
      kubectl("scale deployment #{DEFAULT_DEPLOYMENT} --replicas=1 -n #{DEFAULT_NAMESPACE}")

      puts "Waiting up to #{timeout_s}s for engine health at #{target.server_root_url}/health..."
      t0 = Time.now
      last_print = 0
      while Time.now - t0 < timeout_s
        elapsed = (Time.now - t0).round(1)
        if target.ping_health
          puts "✓ Inference engine is ready in #{elapsed}s (#{target.model_id})"
          return true
        end
        if elapsed.to_i % 3 == 0 && elapsed.to_i != last_print
          puts "... waiting for engine to finish loading model (#{elapsed}s elapsed)"
          last_print = elapsed.to_i
        end
        sleep 0.5
      end

      warn "✗ Timeout waiting #{timeout_s}s for inference engine to become healthy."
      false
    end

    def self.engine_down!
      puts "Scaling #{DEFAULT_DEPLOYMENT} deployment to 0 replicas..."
      kubectl("scale deployment #{DEFAULT_DEPLOYMENT} --replicas=0 -n #{DEFAULT_NAMESPACE}")
      puts "✓ #{DEFAULT_DEPLOYMENT} scaled to 0 replicas."
      true
    end

    def self.engine_status(target: nil)
      target ||= from_engine("qwen36-coder-hybrid")
      replicas = kubectl("get deployment #{DEFAULT_DEPLOYMENT} -n #{DEFAULT_NAMESPACE} -o jsonpath='{.spec.replicas}'", capture: true)
      ready_replicas = kubectl("get deployment #{DEFAULT_DEPLOYMENT} -n #{DEFAULT_NAMESPACE} -o jsonpath='{.status.readyReplicas}'", capture: true)
      ping = target.ping_health
      healthy = target.healthy?

      puts "=== Alpha Engine Status ==="
      puts "Deployment: #{DEFAULT_NAMESPACE}/#{DEFAULT_DEPLOYMENT}"
      puts "Replicas: #{replicas.empty? ? 0 : replicas} (ready: #{ready_replicas.empty? ? 0 : ready_replicas})"
      puts "Endpoint: #{target.base_url}"
      puts "Health (/health): #{ping ? "OK" : "DOWN"}"
      puts "Model (#{target.model_id}): #{healthy ? "READY" : "NOT LOADED"}"

      {
        replicas: replicas.to_i,
        ready_replicas: ready_replicas.to_i,
        healthy: healthy,
        ping: ping
      }
    end

    def initialize(base_url:, model_id:, engine_preset:, context_window: 262_144)
      @base_url = base_url.chomp("/")
      @model_id = model_id
      @engine_preset = engine_preset
      @context_window = context_window
    end

    def server_root_url
      base_url.sub(%r{/v1\z}, "")
    end

    def ping_health
      uri = URI.parse("#{server_root_url}/health")
      response = http_get(uri, open_timeout: 1, read_timeout: 2)
      return false unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body) rescue {}
      payload["status"] == "ok"
    rescue StandardError
      false
    end

    def healthy?
      uri = URI.parse("#{base_url}/models")
      response = http_get(uri, open_timeout: 1, read_timeout: 3)
      return false unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body) rescue {}
      models = Array(payload["data"]).flat_map do |m|
        [m["id"], *m["aliases"]]
      end.compact
      models.empty? || models.include?(model_id)
    rescue StandardError
      false
    end

    def ensure_awake!(timeout_s: 30)
      return true if healthy?

      puts "Inference engine is down/unreachable at #{base_url}. Auto-waking..."
      self.class.engine_up(preset: engine_preset, timeout_s: timeout_s)
    end

    def erase_slots!
      slots_uri = URI.parse("#{server_root_url}/slots")
      res = http_get(slots_uri, open_timeout: 2, read_timeout: 3)
      return false unless res.is_a?(Net::HTTPSuccess)

      slots = JSON.parse(res.body) rescue []
      Array(slots).each do |slot|
        slot_id = slot["id"]
        next if slot_id.nil?

        erase_uri = URI.parse("#{server_root_url}/slots/#{slot_id}?action=erase")
        http_post(erase_uri, open_timeout: 2, read_timeout: 3)
      end
      true
    rescue StandardError
      false
    end

    private
      def http_get(uri, open_timeout: 2, read_timeout: 5)
        Net::HTTP.start(uri.host, uri.port, open_timeout: open_timeout, read_timeout: read_timeout) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
      end

      def http_post(uri, open_timeout: 2, read_timeout: 5)
        Net::HTTP.start(uri.host, uri.port, open_timeout: open_timeout, read_timeout: read_timeout) do |http|
          http.request(Net::HTTP::Post.new(uri))
        end
      end
  end
end
