# Re-score Run 13's SAVED responses with the fixed scorer. No new model calls —
# this isolates the delta from the scorer fix alone.
require "json"
require_relative "documents_v2"
require_relative "scorer"

old = JSON.parse(File.read(File.join(__dir__, "results_v2_ab.ORIGINAL.json")), symbolize_names: true)
out = {}

%i[A B].each do |v|
  rows = old[:per_document][v].map do |row|
    doc = DocumentsV2.all.find { it[:id] == row[:id] }
    findings = row[:findings].map { |f| f.transform_keys(&:to_s) }
    s = Scorer.score_document(doc, findings)
    s[:clean] = row[:clean]
    s[:findings] = findings
    s
  end
  out[v] = rows
end

# variant B, low-confidence discarded
b_high = out[:B].map do |row|
  doc = DocumentsV2.all.find { it[:id] == row[:id] }
  kept = row[:findings].select { it["confidence"] == "high" }
  s = Scorer.score_document(doc, kept); s[:clean] = row[:clean]; s
end

clean_fp = ->(rows) { rows.select { it[:clean] }.sum { it[:false_positives].size } }

result = {
  variant_A:           { aggregate: Scorer.aggregate(out[:A]), clean_false_positives: clean_fp.(out[:A]) },
  variant_B_all:       { aggregate: Scorer.aggregate(out[:B]), clean_false_positives: clean_fp.(out[:B]) },
  variant_B_high_only: { aggregate: Scorer.aggregate(b_high),  clean_false_positives: clean_fp.(b_high) },
  ambiguous_cases: out[:B].flat_map { |r| (r[:ambiguous] || []).map { |a| { doc: r[:id] }.merge(a) } }
}
File.write(File.join(__dir__, "results_v2_ab_FIXED.json"), JSON.pretty_generate(result))
puts JSON.pretty_generate(result[:variant_A][:aggregate][:overall])
puts "wrote results_v2_ab_FIXED.json"
