# Part 1: replay Run 14's SAVED raw responses through scorer with/without the
# mechanical filter. No new model calls — isolates the filter's effect alone.
require "json"
require_relative "documents_v3"
require_relative "scorer"
require_relative "span_filter"

saved = JSON.parse(File.read(File.join(__dir__, "results_v3.json")))
rows = saved["per_document"]

score = lambda do |filtered|
  all_dropped = []
  scored = rows.map do |row|
    doc = DocumentsV3.all.find { it[:id] == row["id"] }
    findings = row["findings"]
    if filtered
      kept, dropped = SpanFilter.apply(findings)
      dropped.each { all_dropped << { doc: row["id"] }.merge(it) }
      findings = kept
    end
    s = Scorer.score_document(doc, findings)
    s[:clean] = row["clean"]
    s
  end
  [ scored, all_dropped ]
end

before, = score.call(false)
after, dropped = score.call(true)

clean_fp = ->(rs) { rs.select { it[:clean] }.sum { it[:false_positives].size } }
fp_texts = ->(rs) { rs.flat_map { |r| r[:false_positives].map { |f| { doc: r[:id], text: f[:text], type: f[:type] } } } }

survivors = fp_texts.call(after)
caught_by_filter = fp_texts.call(before).reject { |f| survivors.any? { |s| s[:doc] == f[:doc] && s[:text] == f[:text] } }

out = {
  before: { aggregate: Scorer.aggregate(before), clean_false_positives: clean_fp.call(before) },
  after:  { aggregate: Scorer.aggregate(after),  clean_false_positives: clean_fp.call(after) },
  dropped_by_filter: dropped,
  false_positives_caught: caught_by_filter,
  false_positives_surviving: survivors
}
File.write(File.join(__dir__, "results_v3_filtered_replay.json"), JSON.pretty_generate(out))

b = out[:before][:aggregate][:overall]; a = out[:after][:aggregate][:overall]
puts "REPLAY — Run 14 saved responses, filter effect isolated"
puts format("  before: caught %d/%d (%.1f%%)  FP %d  precision %.1f%%  clean-FP %d",
            b[:caught], b[:planted], b[:recall], b[:false_positives], b[:precision], out[:before][:clean_false_positives])
puts format("  after : caught %d/%d (%.1f%%)  FP %d  precision %.1f%%  clean-FP %d",
            a[:caught], a[:planted], a[:recall], a[:false_positives], a[:precision], out[:after][:clean_false_positives])
puts format("  real detections lost to filter: %d", b[:caught] - a[:caught])
puts "\n  filter dropped #{dropped.size} spans:"
dropped.group_by { it[:reason] }.each { |r, ds| puts "    #{r}: #{ds.size} — #{ds.map { it[:text] }.inspect[0, 150]}" }
puts "\n  FPs caught by filter: #{caught_by_filter.size} / #{b[:false_positives]}"
puts "  FPs surviving:        #{survivors.size}"
survivors.each { puts "    #{it[:doc]}  #{it[:type]}  #{it[:text].inspect}" }
