# frozen_string_literal: true

# Single measurement run: send each synthetic document to the local model, ask for
# PII spans as schema-constrained JSON, score against ground truth.
#
# This is a BASELINE run. It does not iterate on prompt or model to chase a score.
#
# Abort conditions (checked after every document):
#   - any single request exceeding REQUEST_TIMEOUT
#   - MAX_CONSECUTIVE_BAD malformed/unparseable responses in a row

require "faraday"
require "json"
require "json_schemer"
require_relative "documents"
require_relative "scorer"

ENDPOINT          = ENV.fetch("PII_ENDPOINT", "http://127.0.0.1:8090/v1/chat/completions")
MODEL             = ENV.fetch("PII_MODEL", "llama3.1:8b")
REQUEST_TIMEOUT   = 60
MAX_CONSECUTIVE_BAD = 3

# The schema is enforced server-side by llama.cpp's grammar-constrained decoding
# (verified: an enum-constrained probe could not emit an out-of-enum value).
FINDING_SCHEMA = {
  "type" => "object",
  "properties" => {
    "findings" => {
      "type" => "array",
      "items" => {
        "type" => "object",
        "properties" => {
          "text" => { "type" => "string" },
          "type" => { "type" => "string", "enum" => Documents::TYPES }
        },
        "required" => %w[text type],
        "additionalProperties" => false
      }
    }
  },
  "required" => ["findings"],
  "additionalProperties" => false
}.freeze

VALIDATOR = JSONSchemer.schema(FINDING_SCHEMA)

PROMPT = <<~P
  You are a PII detection tool. Find every piece of personally identifiable
  information in the document below.

  For each one, return the exact text span as it appears in the document, and its
  type. Valid types: name, email, phone, address, ssn, dob.

  Include PII even when it is not labelled — a person named only by role or
  relationship, a phone number in a non-US format, an address written inline in a
  sentence, or a date of birth implied by an age and a reference date all count.

  Return only what is actually present. Do not invent findings.

  DOCUMENT:
  ---
  %<text>s
  ---
P

def connection
  Faraday.new(url: ENDPOINT) do |f|
    f.request :json
    f.options.timeout = REQUEST_TIMEOUT
    f.options.open_timeout = 10
  end
end

def query(conn, doc)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  resp = conn.post do |r|
    r.headers["Content-Type"] = "application/json"
    r.body = {
      model: MODEL,
      messages: [ { role: "user", content: format(PROMPT, text: doc[:text]) } ],
      response_format: {
        type: "json_schema",
        json_schema: { name: "pii_findings", strict: true, schema: FINDING_SCHEMA }
      }
    }
  end
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

  body = JSON.parse(resp.body)
  content = body.dig("choices", 0, "message", "content").to_s
  parsed = JSON.parse(content)
  valid = VALIDATOR.valid?(parsed)

  { ok: valid, findings: parsed["findings"] || [], elapsed: elapsed, raw: content, error: nil }
rescue Faraday::TimeoutError
  { ok: false, findings: [], elapsed: REQUEST_TIMEOUT, raw: nil, error: "timeout" }
rescue JSON::ParserError => e
  { ok: false, findings: [], elapsed: elapsed || 0, raw: content, error: "unparseable: #{e.message[0, 60]}" }
rescue StandardError => e
  { ok: false, findings: [], elapsed: 0, raw: nil, error: "#{e.class}: #{e.message[0, 80]}" }
end

conn = connection
results = []
consecutive_bad = 0
aborted = nil

puts "PII detection baseline — #{Documents.all.size} documents, #{Documents.ground_truth_count} planted items"
puts "endpoint=#{ENDPOINT} model=#{MODEL}"
puts "-" * 78

Documents.all.each_with_index do |doc, i|
  r = query(conn, doc)

  if r[:error] == "timeout" || r[:elapsed] > REQUEST_TIMEOUT
    aborted = "document #{doc[:id]} exceeded #{REQUEST_TIMEOUT}s"
    puts format("  %-8s %-8s ABORT — %s", doc[:id], doc[:tier], aborted)
    break
  end

  unless r[:ok]
    consecutive_bad += 1
    puts format("  %-8s %-8s BAD (%d in a row) — %s", doc[:id], doc[:tier], consecutive_bad, r[:error] || "schema-invalid")
    if consecutive_bad >= MAX_CONSECUTIVE_BAD
      aborted = "#{MAX_CONSECUTIVE_BAD} consecutive malformed responses"
      puts "  ABORT — #{aborted}"
      break
    end
    next
  end

  consecutive_bad = 0
  scored = Scorer.score_document(doc, r[:findings])
  scored[:elapsed] = r[:elapsed].round(2)
  scored[:flagged] = r[:findings].size
  results << scored

  puts format("  %-8s %-8s planted=%d caught=%d fp=%d typeerr=%d  %.1fs",
              doc[:id], doc[:tier], scored[:planted], scored[:caught],
              scored[:false_positives].size, scored[:type_errors], r[:elapsed])
end

summary = {
  aborted: aborted,
  documents_scored: results.size,
  aggregate: Scorer.aggregate(results),
  by_pii_type: Scorer.by_pii_type(results),
  per_document: results
}

File.write(File.join(__dir__, "results.json"), JSON.pretty_generate(summary))
puts "-" * 78
puts JSON.pretty_generate(summary[:aggregate])
puts "\nwrote results.json"
puts "ABORTED: #{aborted}" if aborted
