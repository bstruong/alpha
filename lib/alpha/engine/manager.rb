# frozen_string_literal: true

require "json"
require "uri"
require_relative "../http"

module Alpha
  module Engine
    # Thin HTTP client for an OpenAI-compatible inference server (llama-server, etc.).
    #
    # Cluster wake / lease / kubectl control for JARVIS lives in homelab-k3s:
    #   scripts/jarvis-up.sh, jarvis-down.sh, jarvis-lease.sh
    #   scripts/alpha-engine/manager.rb  (archived Ruby kubectl client)
    class Manager
      DEFAULT_BASE_URL = "http://127.0.0.1:8080/v1"

      OPS_HINT = <<~HINT.freeze
        Inference lifecycle (wake/sleep/lease) is not part of the Alpha gem.
        Use homelab-k3s: ./scripts/jarvis-up.sh, ./scripts/jarvis-down.sh,
        ./scripts/jarvis-lease.sh — see scripts/alpha-engine/README.md
      HINT

      attr_reader :base_url

      def initialize(base_url: ENV.fetch("OPENAI_BASE_URL", DEFAULT_BASE_URL), **_ignored)
        @base_url = base_url.to_s.chomp("/")
      end

      def server_root_url
        base_url.sub(%r{/v1\z}, "")
      end

      def healthy?(expected_preset: nil)
        uri = URI.parse("#{server_root_url}/health")
        res = Alpha::Http.start(uri, open_timeout: 2, read_timeout: 3) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
        return false unless res.is_a?(Net::HTTPSuccess)

        models_uri = URI.parse("#{base_url}/models")
        res2 = Alpha::Http.start(models_uri, open_timeout: 2, read_timeout: 3) do |http|
          http.request(Net::HTTP::Get.new(models_uri))
        end
        return false unless res2.is_a?(Net::HTTPSuccess)

        return true if expected_preset.nil?

        body = JSON.parse(res2.body) rescue {}
        loaded_ids = Array(body["data"]).flat_map { |m| [m["id"], *Array(m["aliases"])] }.compact
        loaded_ids.any? { |id| id.to_s.include?(expected_preset.to_s) }
      rescue StandardError
        false
      end

      def status
        {
          deployment_found: false,
          running: healthy?,
          healthy: healthy?,
          base_url: base_url,
          note: "HTTP-only status; use homelab-k3s jarvis-status.sh for cluster state"
        }
      end

      def up(**)
        raise OPS_HINT
      end

      def down(**)
        raise OPS_HINT
      end

      def ensure_running!(**)
        return true if healthy?

        raise OPS_HINT
      end

      def acquire_lease!(**)
        raise OPS_HINT
      end

      def release_lease!(**)
        raise OPS_HINT
      end
    end
  end
end
