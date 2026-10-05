# frozen_string_literal: true

# Round 2: one corpus, two schema variants, single comparative measurement.
#
#   Variant A (control) — Run 12's schema: forced PII-type enum, no way to hedge.
#   Variant B (test)    — same, plus a required confidence: "high" | "low" per span.
#
# The question: does giving the model a real way to express uncertainty reduce the
# false positives that Run 12 found clustered on ambiguous text, and does it cost
# recall (hedging on PII it would otherwise have caught outright)?
#
# Variant B is scored twice, because these answer different questions:
#   B(all)  — every finding counted. Does merely offering the option change what
#             the model flags at all?
#   B(high) — low-confidence findings discarded. Is filtering on it actually useful?
#
# No prompt or schema tuning. Single run, both variants, full corpus.
#
# Abort: 60s per request; 3 consecutive malformed responses.

require "faraday"
require "json"
require "json_schemer"
require_relative "documents_v2"
require_relative "scorer"

ENDPOINT            = ENV.fetch("PII_ENDPOINT", "http://127.0.0.1:8090/v1/chat/completions")
MODEL               = ENV.fetch("PII_MODEL", "llama3.1:8b")
REQUEST_TIMEOUT     = 60
MAX_CONSECUTIVE_BAD = 3

def finding_props(with_confidence:)
  props = {
    "text" => { "type" => "string" },
    "type" => { "type" => "string", "enum" => DocumentsV2::TYPES }
  }
  required = %w[text type]
  if with_confidence
    props["confidence"] = { "type" => "string", "enum" => %w[high low] }
    required << "confidence"
  end
  [ props, required ]
end

def schema_for(with_confidence:)
  props, required = finding_props(with_confidence: with_confidence)
  {
    "type" => "object",
    "properties" => {
      "findings" => {
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => props,
          "required" => required,
          "additionalProperties" => false
        }
      }
    },
    "required" => ["findings"],
    "additionalProperties" => false
  }
end

BASE_PROMPT = <<~P
  You are a PII detection tool. Find every piece of personally identifiable
  information in the document below.

  For each one, return the exact text span as it appears in the document, and its
  type. Valid types: name, email, phone, address, ssn, dob.

  Include PII even when it is not labelled — a person named only by role or
  relationship, a phone number in a non-US format, an address written inline in a
  sentence, or a date of birth implied by an age and a reference date all count.

  Return only what is actually present. Do not invent findings. If the document
  contains no PII, return an empty list.
P

CONFIDENCE_CLAUSE = <<~P
  For each finding also give a confidence: "high" if you are sure the span really
  is that kind of PII, "low" if you are unsure or the text is ambiguous. Use "low"
  rather than guessing a type you are not confident about.
P

DOC_CLAUSE = <<~P

  DOCUMENT:
  ---
  %<text>s
  ---
P

VARIANTS = {
  "A" => { confidence: false, prompt: BASE_PROMPT + DOC_CLAUSE },
  "B" => { confidence: true,  prompt: BASE_PROMPT + CONFIDENCE_CLAUSE + DOC_CLAUSE }
}.freeze

def connection
  Faraday.new(url: ENDPOINT) do |f|
    f.request :json
    f.options.timeout = REQUEST_TIMEOUT
    f.options.open_timeout = 10
  end
end

def query(conn, doc, variant)
  cfg = VARIANTS.fetch(variant)
  schema = schema_for(with_confidence: cfg[:confidence])
  validator = JSONSchemer.schema(schema)
  content = nil
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  resp = conn.post do |r|
    r.headers["Content-Type"] = "application/json"
    r.body = {
      model: MODEL,
      messages: [ { role: "user", content: format(cfg[:prompt], text: doc[:text]) } ],
      response_format: {
        type: "json_schema",
        json_schema: { name: "pii_findings", strict: true, schema: schema }
      }
    }
  end
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

  content = resp.body.is_a?(String) ? JSON.parse(resp.body).dig("choices", 0, "message", "content") : nil
  parsed = JSON.parse(content.to_s)
  { ok: validator.valid?(parsed), findings: parsed["findings"] || [], elapsed: elapsed, error: nil }
rescue Faraday::TimeoutError
  { ok: false, findings: [], elapsed: REQUEST_TIMEOUT, error: "timeout" }
rescue JSON::ParserError => e
  { ok: false, findings: [], elapsed: 0, error: "unparseable: #{e.message[0, 60]}" }
rescue StandardError => e
  { ok: false, findings: [], elapsed: 0, error: "#{e.class}: #{e.message[0, 80]}" }
end

def run_variant(conn, variant)
  results = []
  consecutive_bad = 0
  aborted = nil
  conf_counts = Hash.new { |h, k| h[k] = { "high" => 0, "low" => 0 } }

  DocumentsV2.all.each do |doc|
    r = query(conn, doc, variant)

    if r[:error] == "timeout"
      aborted = "#{doc[:id]} exceeded #{REQUEST_TIMEOUT}s"
      warn "  [#{variant}] #{doc[:id]} ABORT — #{aborted}"
      break
    end

    unless r[:ok]
      consecutive_bad += 1
      warn "  [#{variant}] #{doc[:id]} BAD (#{consecutive_bad}) — #{r[:error] || 'schema-invalid'}"
      if consecutive_bad >= MAX_CONSECUTIVE_BAD
        aborted = "#{MAX_CONSECUTIVE_BAD} consecutive malformed responses"
        warn "  [#{variant}] ABORT — #{aborted}"
        break
      end
      next
    end
    consecutive_bad = 0

    findings = r[:findings]
    findings.each { conf_counts[doc[:tier]][it["confidence"]] += 1 if it["confidence"] }

    scored = Scorer.score_document(doc, findings)
    scored[:clean] = !!doc[:clean]
    scored[:elapsed] = r[:elapsed].round(2)
    scored[:flagged] = findings.size
    scored[:findings] = findings
    results << scored

    puts format("  [%s] %-12s %-8s planted=%d caught=%d fp=%d %s %.1fs",
                variant, doc[:id], doc[:tier], scored[:planted], scored[:caught],
                scored[:false_positives].size,
                r[:findings].any? { it["confidence"] } ? "conf=#{findings.count { it['confidence'] == 'low' }}low" : "",
                r[:elapsed])
  end

  { results: results, aborted: aborted, confidence: conf_counts }
end

# Re-score a variant-B run keeping only high-confidence findings.
def rescore_high_only(results)
  results.map do |row|
    doc = DocumentsV2.all.find { it[:id] == row[:id] }
    kept = row[:findings].select { it["confidence"] == "high" }
    s = Scorer.score_document(doc, kept)
    s[:clean] = row[:clean]
    s[:flagged] = kept.size
    s[:findings] = kept
    s
  end
end

def clean_fp(results)
  results.select { it[:clean] }.sum { it[:false_positives].size }
end

conn = connection
puts "Round 2 — #{DocumentsV2.all.size} documents, #{DocumentsV2.ground_truth_count} planted items"
puts "tiers: #{DocumentsV2.all.group_by { it[:tier] }.transform_values(&:size)}  clean docs: #{DocumentsV2.clean.size}"
puts "-" * 82

a = run_variant(conn, "A")
puts "-" * 82
b = run_variant(conn, "B")
puts "-" * 82

b_high = rescore_high_only(b[:results])

summary = {
  aborted: { A: a[:aborted], B: b[:aborted] },
  variant_A: { aggregate: Scorer.aggregate(a[:results]), clean_false_positives: clean_fp(a[:results]) },
  variant_B_all: { aggregate: Scorer.aggregate(b[:results]), clean_false_positives: clean_fp(b[:results]) },
  variant_B_high_only: { aggregate: Scorer.aggregate(b_high), clean_false_positives: clean_fp(b_high) },
  confidence_usage: b[:confidence],
  per_document: { A: a[:results], B: b[:results] }
}

File.write(File.join(__dir__, "results_v2_ab.json"), JSON.pretty_generate(summary))
puts JSON.pretty_generate(summary.reject { |k, _| k == :per_document })
puts "\nwrote results_v2_ab.json"
