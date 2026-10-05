# Round 3: structural/adversarial corpus, variant B only (confidence schema —
# Run 13 settled that comparison). Fixed alias-aware scorer. Single measurement.
require "faraday"; require "json"; require "json_schemer"
require_relative "documents_v3"; require_relative "scorer"

ENDPOINT = ENV.fetch("PII_ENDPOINT", "http://127.0.0.1:8090/v1/chat/completions")
MODEL    = ENV.fetch("PII_MODEL", "llama3.1:8b")
REQUEST_TIMEOUT = 60
MAX_CONSECUTIVE_BAD = 3

SCHEMA = {
  "type" => "object",
  "properties" => { "findings" => { "type" => "array", "items" => {
    "type" => "object",
    "properties" => {
      "text" => { "type" => "string" },
      "type" => { "type" => "string", "enum" => DocumentsV3::TYPES },
      "confidence" => { "type" => "string", "enum" => %w[high low] }
    },
    "required" => %w[text type confidence], "additionalProperties" => false } } },
  "required" => ["findings"], "additionalProperties" => false
}.freeze
VALIDATOR = JSONSchemer.schema(SCHEMA)

PROMPT = <<~P
  You are a PII detection tool. Find every piece of personally identifiable
  information in the document below.

  For each one, return the exact text span as it appears in the document, and its
  type. Valid types: name, email, phone, address, ssn, dob.

  Include PII even when it is not labelled — a person named only by role or
  relationship, a phone number in a non-US format, an address written inline in a
  sentence, or a date of birth implied by an age and a reference date all count.

  Return only what is actually present. Do not invent findings. If the document
  contains no PII, return an empty list.

  For each finding also give a confidence: "high" if you are sure the span really
  is that kind of PII, "low" if you are unsure or the text is ambiguous. Use "low"
  rather than guessing a type you are not confident about.

  DOCUMENT:
  ---
  %<text>s
  ---
P

conn = Faraday.new(url: ENDPOINT) do |f|
  f.request :json
  f.options.timeout = REQUEST_TIMEOUT
  f.options.open_timeout = 10
end

results = []; consecutive_bad = 0; aborted = nil
conf = Hash.new { |h, k| h[k] = { "high" => 0, "low" => 0 } }

puts "Round 3 — #{DocumentsV3.all.size} docs, #{DocumentsV3.ground_truth_count} planted, variant B"
puts "-" * 84

DocumentsV3.all.each do |doc|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    resp = conn.post do |r|
      r.headers["Content-Type"] = "application/json"
      r.body = { model: MODEL,
                 messages: [ { role: "user", content: format(PROMPT, text: doc[:text]) } ],
                 response_format: { type: "json_schema",
                                    json_schema: { name: "pii", strict: true, schema: SCHEMA } } }
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    content = JSON.parse(resp.body).dig("choices", 0, "message", "content")
    parsed = JSON.parse(content.to_s)
    ok = VALIDATOR.valid?(parsed)
    findings = parsed["findings"] || []
  rescue Faraday::TimeoutError
    aborted = "#{doc[:id]} exceeded #{REQUEST_TIMEOUT}s"; puts "  #{doc[:id]} ABORT — #{aborted}"; break
  rescue StandardError => e
    ok = false; findings = []; elapsed = 0; err = "#{e.class}: #{e.message[0,60]}"
  end

  unless ok
    consecutive_bad += 1
    puts "  #{doc[:id]} BAD (#{consecutive_bad}) — #{err || 'schema-invalid'}"
    if consecutive_bad >= MAX_CONSECUTIVE_BAD
      aborted = "#{MAX_CONSECUTIVE_BAD} consecutive malformed responses"; puts "  ABORT — #{aborted}"; break
    end
    next
  end
  consecutive_bad = 0

  findings.each { conf[doc[:tier]][it["confidence"]] += 1 }
  s = Scorer.score_document(doc, findings)
  s[:clean] = !!doc[:clean]; s[:findings] = findings; s[:elapsed] = elapsed.round(2)
  results << s
  puts format("  %-10s %-12s planted=%2d caught=%2d fp=%d low=%d %.1fs",
              doc[:id], doc[:tier], s[:planted], s[:caught], s[:false_positives].size,
              findings.count { it["confidence"] == "low" }, elapsed)
end

high_only = results.map do |row|
  d = DocumentsV3.all.find { it[:id] == row[:id] }
  s = Scorer.score_document(d, row[:findings].select { it["confidence"] == "high" })
  s[:clean] = row[:clean]; s
end
cfp = ->(rows) { rows.select { it[:clean] }.sum { it[:false_positives].size } }

out = { aborted: aborted,
        variant_B_all: { aggregate: Scorer.aggregate(results), clean_false_positives: cfp.(results) },
        variant_B_high_only: { aggregate: Scorer.aggregate(high_only), clean_false_positives: cfp.(high_only) },
        by_pii_type: Scorer.by_pii_type(results),
        confidence_usage: conf,
        per_document: results }
File.write(File.join(__dir__, "results_v3.json"), JSON.pretty_generate(out))
puts "-" * 84
puts JSON.pretty_generate(out.reject { |k,_| k == :per_document })
