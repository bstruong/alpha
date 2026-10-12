# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Thin client over Ollama's local HTTP API. Sends a prompt + JSON schema
# (Ollama's structured-output `format` parameter) and returns the raw
# response plus timing — this mirrors how ASSASSIN's extraction service
# would actually invoke the model, so it tests the real code path.
#
# Depend on abstractions — the host is injected, defaulting to local.
class OllamaClient
  GENERATE_PATH = "/api/generate"

  # Result of one extraction call. parsed is nil if the response wasn't
  # valid JSON — that itself is a measured outcome, not an error to raise.
  Response = Data.define(:raw_text, :parsed, :json_valid, :tokens, :duration_seconds) do
    def tokens_per_second
      return 0.0 if duration_seconds.zero?

      (tokens / duration_seconds).round(2)
    end
  end

  def initialize(host: "http://localhost:11434", read_timeout: 300)
    @host = host
    @read_timeout = read_timeout
  end

  def extract(model:, prompt:, schema:)
    body = request_body(model: model, prompt: prompt, schema: schema)
    payload = post(body)
    build_response(payload)
  end

  private

  attr_reader :host, :read_timeout

  def request_body(model:, prompt:, schema:)
    {
      model: model,
      prompt: prompt,
      stream: false,
      format: schema,            # structured-output enforcement
      options: { temperature: 0 }
    }
  end

  def post(body)
    uri = URI.join(host, GENERATE_PATH)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = read_timeout

    request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
    request.body = JSON.generate(body)

    JSON.parse(http.request(request).body)
  end

  def build_response(payload)
    raw = payload.fetch("response", "")
    parsed, valid = parse_json(raw)

    Response.new(
      raw_text: raw,
      parsed: parsed,
      json_valid: valid,
      tokens: payload.fetch("eval_count", 0),
      duration_seconds: payload.fetch("eval_duration", 0) / 1_000_000_000.0
    )
  end

  # Returns [parsed_or_nil, valid_boolean] — never raises on bad JSON.
  def parse_json(text)
    [JSON.parse(text), true]
  rescue JSON::ParserError
    [nil, false]
  end
end
