# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "shellwords"
require "socket"
require "timeout"
require "uri"

module Alpha
  module Engine
    # Manages the on-demand lifecycle of the inference server running under k3s
    # on Watchtower (AM5 homelab node at 192.168.1.92). Supports scaling to zero
    # to reclaim 20 GB RAM & 11 GB VRAM, waking on demand, switching model presets,
    # and verifying health.
    class Manager
      DEFAULT_HOST = "btruong@192.168.1.92"
      DEFAULT_NAMESPACE = "alpha"
      DEFAULT_DEPLOYMENT = "alpha-llama"
      DEFAULT_BASE_URL = "http://192.168.1.92:8080/v1"

      attr_reader :host, :namespace, :deployment, :base_url

      def initialize(
        host: ENV.fetch("ALPHA_ENGINE_HOST", DEFAULT_HOST),
        namespace: ENV.fetch("ALPHA_ENGINE_NAMESPACE", DEFAULT_NAMESPACE),
        deployment: ENV.fetch("ALPHA_ENGINE_DEPLOYMENT", DEFAULT_DEPLOYMENT),
        base_url: ENV.fetch("OPENAI_BASE_URL", DEFAULT_BASE_URL)
      )
        @host = host
        @namespace = namespace
        @deployment = deployment
        @base_url = base_url.chomp("/")
      end

      def local?
        hostname = Socket.gethostname.downcase
        hostname.include?("watchtower") || host == "localhost" || host == "127.0.0.1"
      end

      def server_root_url
        base_url.sub(%r{/v1\z}, "")
      end

      def healthy?
        uri = URI.parse("#{server_root_url}/health")
        res = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 3) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
        return true if res.is_a?(Net::HTTPSuccess)

        # Fallback to /v1/models
        models_uri = URI.parse("#{base_url}/models")
        res2 = Net::HTTP.start(models_uri.host, models_uri.port, open_timeout: 2, read_timeout: 3) do |http|
          http.request(Net::HTTP::Get.new(models_uri))
        end
        res2.is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      def status
        json_out, err, status = run_cmd("kubectl -n #{namespace} get deployment #{deployment} -o json")
        unless status.success?
          return {
            deployment_found: false,
            error: err.strip,
            running: false,
            healthy: healthy?
          }
        end

        data = JSON.parse(json_out) rescue {}
        spec_replicas = data.dig("spec", "replicas").to_i
        ready_replicas = data.dig("status", "readyReplicas").to_i
        args = data.dig("spec", "template", "spec", "containers", 0, "args") || []

        model_arg = nil
        alias_arg = nil
        args.each_cons(2) do |k, v|
          model_arg = v if k == "--model"
          alias_arg = v if k == "--alias"
        end

        active_preset = resolve_preset_from_model(model_arg, alias_arg)

        {
          deployment_found: true,
          deployment: deployment,
          namespace: namespace,
          spec_replicas: spec_replicas,
          ready_replicas: ready_replicas,
          running: ready_replicas.positive?,
          healthy: healthy?,
          active_preset: active_preset,
          model_path: model_arg,
          alias: alias_arg
        }
      end

      def up(preset: nil, wait: true, timeout: 60)
        current = status
        raise "Deployment #{deployment} not found in namespace #{namespace}: #{current[:error]}" unless current[:deployment_found]

        if preset && preset.to_s != current[:active_preset]
          patch_preset!(preset.to_s)
        end

        if current[:spec_replicas].zero?
          _out, err, status = run_cmd("kubectl -n #{namespace} scale deployment/#{deployment} --replicas=1")
          raise "Failed to scale deployment #{deployment} to 1: #{err}" unless status.success?
        end

        return true unless wait

        wait_until_healthy(timeout: timeout)
      end

      def down
        _out, err, status = run_cmd("kubectl -n #{namespace} scale deployment/#{deployment} --replicas=0")
        raise "Failed to scale deployment #{deployment} to 0: #{err}" unless status.success?

        true
      end

      def ensure_running!(preset: nil, timeout: 60)
        st = status
        if st[:running] && st[:healthy] && (preset.nil? || preset.to_s == st[:active_preset])
          return true
        end

        up(preset: preset, wait: true, timeout: timeout)
      end

      def patch_preset!(preset_name)
        model_file, model_alias = resolve_model_and_alias(preset_name)
        args_json_out, _err, status = run_cmd("kubectl -n #{namespace} get deployment #{deployment} -o jsonpath='{.spec.template.spec.containers[0].args}'")
        raise "Failed to fetch container args: #{_err}" unless status.success?

        args = JSON.parse(args_json_out) rescue []
        new_args = []
        skip_next = false
        args.each_with_index do |arg, idx|
          if skip_next
            skip_next = false
            next
          end

          if arg == "--model"
            new_args << "--model" << model_file
            skip_next = true
          elsif arg == "--alias"
            new_args << "--alias" << model_alias
            skip_next = true
          else
            new_args << arg
          end
        end

        patch_payload = [
          {
            "op" => "replace",
            "path" => "/spec/template/spec/containers/0/args",
            "value" => new_args
          }
        ].to_json

        escaped_patch = patch_payload.gsub('"', '\"')
        patch_cmd = %(kubectl -n #{namespace} patch deployment #{deployment} --type='json' -p="#{escaped_patch}")
        _out, err, status = run_cmd(patch_cmd)
        raise "Failed to patch preset on deployment #{deployment}: #{err}" unless status.success?

        true
      end

      private
        def run_cmd(cmd)
          full_cmd = if local?
            cmd
          else
            "ssh -o BatchMode=yes -o ConnectTimeout=5 #{host} #{Shellwords.escape(cmd)}"
          end
          Open3.capture3(full_cmd)
        end

        def wait_until_healthy(timeout: 60)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
            return true if healthy?

            sleep 1
          end
          raise Timeout::Error, "Inference server at #{base_url} did not become healthy within #{timeout}s"
        end

        def resolve_preset_from_model(model_arg, alias_arg)
          return "qwen25-coder-14b" if model_arg&.include?("14B") || model_arg&.include?("14b") || alias_arg&.include?("14b")
          return "qwen36-coder-hybrid" if model_arg&.include?("Qwen3.6") || alias_arg&.include?("qwen36-coder")
          return "glm47-reap" if model_arg&.include?("GLM-4.7") || alias_arg&.include?("glm47")

          "unknown"
        end

        def resolve_model_and_alias(preset_name)
          case preset_name.to_s
          when "qwen25-coder-14b", "qwen25-14b", "14b"
            [ "/models/qwen2.5-coder-14b-instruct-q4_k_m.gguf", "qwen25-coder-14b,qwen2.5-coder-14b" ]
          when "glm47-reap", "glm47"
            [ "/models/GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf", "glm47-reap,glm-4.7-flash" ]
          when "qwen36-coder-hybrid", "qwen36-coder", "qwen"
            [ "/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf", "qwen36-coder-hybrid,qwen36-coder" ]
          else
            raise ArgumentError, "Unknown preset #{preset_name.inspect}; valid presets are qwen25-coder-14b, qwen36-coder-hybrid, glm47-reap"
          end
        end
    end
  end
end
