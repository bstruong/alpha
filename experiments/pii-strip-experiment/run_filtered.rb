# Part 2: fresh full pipeline pass with the mechanical filter active.
# Variant B schema (settled in Run 13). Filter applied as a distinct post-step
# between inference and scoring; both filtered and unfiltered scores are recorded
# from the SAME raw responses so the filter's effect stays isolated.
require "faraday"; require "json"; require "json_schemer"
require_relative "documents_v2"; require_relative "documents_v3"
require_relative "scorer"; require_relative "span_filter"

ENDPOINT = ENV.fetch("PII_ENDPOINT", "http://127.0.0.1:8090/v1/chat/completions")
MODEL    = ENV.fetch("PII_MODEL", "llama3.1:8b")
REQUEST_TIMEOUT = 60
MAX_CONSECUTIVE_BAD = 3
TYPES = %w[name email phone address ssn dob].freeze

SCHEMA = {
  "type" => "object",
  "properties" => { "findings" => { "type" => "array", "items" => {
    "type" => "object",
    "properties" => { "text" => { "type" => "string" },
                      "type" => { "type" => "string", "enum" => TYPES },
                      "confidence" => { "type" => "string", "enum" => %w[high low] } },
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
  f.request :json; f.options.timeout = REQUEST_TIMEOUT; f.options.open_timeout = 10
end

def run_corpus(conn, docs, label)
  raw = []; consecutive_bad = 0; aborted = nil
  docs.each do |doc|
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ok = false; findings = []; err = nil
    begin
      resp = conn.post do |r|
        r.headers["Content-Type"] = "application/json"
        r.body = { model: MODEL, messages: [ { role: "user", content: format(PROMPT, text: doc[:text]) } ],
                   response_format: { type: "json_schema", json_schema: { name: "pii", strict: true, schema: SCHEMA } } }
      end
      parsed = JSON.parse(JSON.parse(resp.body).dig("choices", 0, "message", "content").to_s)
      ok = VALIDATOR.valid?(parsed); findings = parsed["findings"] || []
    rescue Faraday::TimeoutError
      aborted = "#{doc[:id]} exceeded #{REQUEST_TIMEOUT}s"; puts "  ABORT — #{aborted}"; break
    rescue StandardError => e
      err = "#{e.class}: #{e.message[0, 60]}"
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

    unless ok
      consecutive_bad += 1
      puts "  #{doc[:id]} BAD (#{consecutive_bad}) — #{err || 'schema-invalid'}"
      if consecutive_bad >= MAX_CONSECUTIVE_BAD
        aborted = "#{MAX_CONSECUTIVE_BAD} consecutive malformed"; puts "  ABORT — #{aborted}"; break
      end
      next
    end
    consecutive_bad = 0
    raw << { doc: doc, findings: findings, elapsed: elapsed }
    kept, dropped = SpanFilter.apply(findings)
    s = Scorer.score_document(doc, kept)
    puts format("  [%s] %-10s %-12s planted=%2d caught=%2d fp=%d dropped=%d %.1fs",
                label, doc[:id], doc[:tier], s[:planted], s[:caught], s[:false_positives].size, dropped.size, elapsed)
  end
  [ raw, aborted ]
end

def summarise(raw)
  unfiltered = raw.map { |r| s = Scorer.score_document(r[:doc], r[:findings]); s[:clean] = !!r[:doc][:clean]; s }
  dropped_all = []
  filtered = raw.map do |r|
    kept, dropped = SpanFilter.apply(r[:findings])
    dropped.each { dropped_all << { doc: r[:doc][:id] }.merge(it) }
    s = Scorer.score_document(r[:doc], kept); s[:clean] = !!r[:doc][:clean]; s
  end
  cfp = ->(rs) { rs.select { it[:clean] }.sum { it[:false_positives].size } }
  { unfiltered: { aggregate: Scorer.aggregate(unfiltered), clean_false_positives: cfp.call(unfiltered) },
    filtered:   { aggregate: Scorer.aggregate(filtered),   clean_false_positives: cfp.call(filtered) },
    dropped: dropped_all,
    surviving_fps: filtered.flat_map { |r| r[:false_positives].map { |f| { doc: r[:id], clean: r[:clean] }.merge(f) } } }
end

puts "Fresh full pass — filter ACTIVE — #{DocumentsV3.all.size} v3 + #{DocumentsV2.all.size} v2 docs"
puts "-" * 88
v3_raw, v3_abort = run_corpus(conn, DocumentsV3.all, "v3")
puts "-" * 88
v2_raw, v2_abort = run_corpus(conn, DocumentsV2.all, "v2")
puts "-" * 88

out = { aborted: { v3: v3_abort, v2: v2_abort },
        v3: summarise(v3_raw), v2: summarise(v2_raw) }
File.write(File.join(__dir__, "results_v4_filtered.json"), JSON.pretty_generate(out))

%w[v3 v2].each do |k|
  s = out[k.to_sym]
  u = s[:unfiltered][:aggregate][:overall]; f = s[:filtered][:aggregate][:overall]
  puts "#{k}: unfiltered caught #{u[:caught]}/#{u[:planted]} (#{u[:recall]}%) FP #{u[:false_positives]} prec #{u[:precision]}% clean-FP #{s[:unfiltered][:clean_false_positives]}"
  puts "#{k}: FILTERED   caught #{f[:caught]}/#{f[:planted]} (#{f[:recall]}%) FP #{f[:false_positives]} prec #{f[:precision]}% clean-FP #{s[:filtered][:clean_false_positives]}"
  puts "#{k}: dropped #{s[:dropped].size} spans #{s[:dropped].group_by { it[:reason] }.transform_values(&:size)}"
end
