# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "engine/manager"

module Alpha
  # Points at the AM5 homelab (watchtower) OpenAI-compatible endpoint.
  # Standardizes on http://192.168.1.92:8080/v1 by default so invocations
  # work identically from watchtower (AM5) or metrotower (Haswell desk).
  class InferenceTarget
    DEFAULT_HOST_URL = "http://192.168.1.92:8080"

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

    def initialize(base_url:, model_id:, engine_preset:, context_window: 262_144)
      @base_url = base_url.chomp("/")
      @model_id = model_id
      @engine_preset = engine_preset
      @context_window = context_window
    end

    def server_root_url
      base_url.sub(%r{/v1\z}, "")
    end

    def healthy?
      uri = URI.parse("#{base_url}/models")
      response = http_get(uri)
      return false unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body) rescue {}
      models = Array(payload["data"]).flat_map do |m|
        [m["id"], *m["aliases"]]
      end.compact
      models.empty? || models.include?(model_id)
    rescue StandardError
      false
    end

    def erase_slots!
      slots_uri = URI.parse("#{server_root_url}/slots")
      res = http_get(slots_uri)
      return false unless res.is_a?(Net::HTTPSuccess)

      slots = JSON.parse(res.body) rescue []
      Array(slots).each do |slot|
        slot_id = slot["id"]
        next if slot_id.nil?

        erase_uri = URI.parse("#{server_root_url}/slots/#{slot_id}?action=erase")
        http_post(erase_uri)
      end
      true
    rescue StandardError
      false
    end

    def manager
      @manager ||= Alpha::Engine::Manager.new(base_url: base_url)
    end

    def wake!(wait: true, timeout: 60)
      manager.up(preset: engine_preset, wait: wait, timeout: timeout)
    end

    def sleep!
      manager.down
    end

    def metrics
      uri = URI.parse("#{server_root_url}/metrics")
      res = http_get(uri)
      return {} unless res.is_a?(Net::HTTPSuccess)

      data = {}
      res.body.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        parts = line.split(/\s+/)
        data[parts[0]] = parts[1].to_f if parts.size >= 2
      end
      data
    rescue StandardError
      {}
    end

    private
      def http_get(uri)
        Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 5) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
      end

      def http_post(uri)
        Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 5) do |http|
          http.request(Net::HTTP::Post.new(uri))
        end
      end
  end
end
