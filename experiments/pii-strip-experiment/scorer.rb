# frozen_string_literal: true

# Scores model findings against a document's ground-truth manifest.
#
# Recall and precision are tracked SEPARATELY and never blended into one number:
#   - recall     : of the PII actually planted, how much was caught
#   - false pos  : spans the model flagged that match no planted PII
#
# Matching is deliberately generous on span boundaries, because "Alvarez" for a
# planted "Mrs. Alvarez" is a catch, not a miss. It is strict about *existence*:
# a flagged span only counts as a catch if it overlaps a planted item.
# Type correctness is tracked as a separate axis so a right-span/wrong-label
# result is visible rather than silently scored as a clean hit.
#
# ── Alias matching (added after Run 13) ────────────────────────────────────────
# Run 13 scored "B. Nkemelu" a false positive against planted "Bartholomew
# Nkemelu": normalized, neither string contains the other, so plain substring
# matching called a correct detection wrong.
#
# Person names now additionally match derived short forms — initials+surname,
# surname-only, first-name-only — but ONLY where that form is unambiguous among
# the names planted in the same document. Where two planted people share a form
# (Adrienne Calloway / Adrian Calloway both reduce to "A. Calloway"), the form is
# refused and the attempt is recorded in :ambiguous rather than being silently
# assigned to one of them. Nicknames cannot be derived, so a planted item may
# declare them explicitly via `aliases:`.
module Scorer
  MIN_SPAN = 3
  HONORIFICS = %w[mr mrs ms miss dr prof sir madam].freeze

  module_function

  def normalize(str)
    str.to_s.downcase.gsub(/[^a-z0-9@+]/, "")
  end

  # Name parts with honorifics and punctuation stripped: "Mrs. Alvarez" -> ["Alvarez"]
  def name_tokens(str)
    str.to_s
       .gsub(/[^A-Za-z\s.'-]/, " ")
       .split(/[\s.]+/)
       .reject(&:empty?)
       .reject { HONORIFICS.include?(it.downcase) }
  end

  # Short forms of `planted` that are unambiguous among `siblings` (all planted
  # person-names in the same document, including planted itself).
  def alias_forms(planted, siblings)
    toks = name_tokens(planted)
    return [] if toks.empty?

    first = toks.first
    last  = toks.last
    sib   = siblings.map { name_tokens(it) }.reject(&:empty?)

    candidates = { first: first }
    if toks.size >= 2
      candidates[:surname] = last
      candidates[:initial] = "#{first[0]}#{last}"
    end

    candidates.filter_map do |kind, value|
      owners = sib.count do |t|
        case kind
        when :first   then t.first.casecmp?(value)
        when :surname then t.size >= 2 && t.last.casecmp?(value)
        when :initial then t.size >= 2 && "#{t.first[0]}#{t.last}".casecmp?(value)
        end
      end
      value if owners == 1 # unique to exactly one planted person
    end
  end

  # Short forms that were REFUSED because more than one planted person owns them.
  def ambiguous_forms(planted, siblings)
    toks = name_tokens(planted)
    return [] if toks.size < 2

    sib = siblings.map { name_tokens(it) }.reject(&:empty?)
    { surname: toks.last, initial: "#{toks.first[0]}#{toks.last}" }.filter_map do |kind, value|
      owners = sib.count do |t|
        kind == :surname ? (t.size >= 2 && t.last.casecmp?(value)) : (t.size >= 2 && "#{t.first[0]}#{t.last}".casecmp?(value))
      end
      value if owners > 1
    end
  end

  # A flagged span matches a planted item if either contains the other once
  # normalized. Guards against trivially-short spans matching everything.
  def spans_match?(planted, flagged)
    a = normalize(planted)
    b = normalize(flagged)
    return false if a.length < MIN_SPAN || b.length < MIN_SPAN

    a == b || a.include?(b) || b.include?(a)
  end

  # Name-aware match: substring first, then unambiguous derived/declared aliases.
  #
  # The ambiguity guard gates BOTH paths. Plain substring would otherwise match a
  # bare "Calloway" against "Adrienne Calloway" and silently pick one of two
  # people who share that surname — the conflation this fix exists to prevent.
  def item_match?(item, flagged, all_planted)
    if item[:type] == "name"
      siblings = all_planted.select { it[:type] == "name" }.map { it[:text] }
      fb = normalize(flagged)
      return false if fb.length < MIN_SPAN

      # Refused outright: a short form owned by more than one planted person.
      shared = siblings.flat_map { ambiguous_forms(it, siblings) }.uniq.map { normalize(it) }
      return false if shared.include?(fb)

      return true if spans_match?(item[:text], flagged)

      forms = alias_forms(item[:text], siblings) + Array(item[:aliases])
      return forms.any? { normalize(it) == fb }
    end

    spans_match?(item[:text], flagged)
  end

  # Flagged spans that were refused only because the short form is shared by two
  # planted people — surfaced, not silently resolved.
  def ambiguous_hits(planted, findings)
    names = planted.select { it[:type] == "name" }.map { it[:text] }
    refused = names.flat_map { ambiguous_forms(it, names) }.uniq.map { normalize(it) }
    return [] if refused.empty?

    findings.filter_map do |f|
      fb = normalize(f["text"])
      { text: f["text"], type: f["type"] } if refused.include?(fb)
    end
  end

  # findings: [{ "text" => ..., "type" => ... }]
  def score_document(doc, findings)
    planted = doc[:pii]
    used    = []

    caught = planted.map do |item|
      hit = findings.find do |f|
        !used.include?(f.object_id) && item_match?(item, f["text"], planted)
      end
      used << hit.object_id if hit
      {
        type: item[:type],
        text: item[:text],
        caught: !hit.nil?,
        matched_span: hit && hit["text"],
        flagged_as: hit && hit["type"],
        type_correct: hit ? hit["type"].to_s == item[:type] : nil
      }
    end

    # Anything the model flagged that matched no planted item at all.
    false_positives = findings.reject do |f|
      planted.any? { item_match?(it, f["text"], planted) }
    end

    {
      id: doc[:id],
      tier: doc[:tier],
      planted: planted.size,
      caught: caught.count { it[:caught] },
      missed: caught.reject { it[:caught] },
      type_errors: caught.count { it[:caught] && it[:type_correct] == false },
      false_positives: false_positives.map { { text: it["text"], type: it["type"] } },
      ambiguous: ambiguous_hits(planted, findings),
      detail: caught
    }
  end

  # Aggregates per-document results, broken out by tier — the point of the run.
  def aggregate(results)
    by_tier = results.group_by { it[:tier] }.transform_values do |rows|
      planted = rows.sum { it[:planted] }
      caught  = rows.sum { it[:caught] }
      fps     = rows.sum { it[:false_positives].size }
      {
        documents: rows.size,
        planted: planted,
        caught: caught,
        missed: planted - caught,
        recall: planted.zero? ? 0.0 : (caught.to_f / planted * 100).round(1),
        false_positives: fps,
        type_errors: rows.sum { it[:type_errors] }
      }
    end

    planted = results.sum { it[:planted] }
    caught  = results.sum { it[:caught] }
    fps     = results.sum { it[:false_positives].size }
    flagged = caught + fps

    by_tier.merge(
      overall: {
        documents: results.size,
        planted: planted,
        caught: caught,
        missed: planted - caught,
        recall: planted.zero? ? 0.0 : (caught.to_f / planted * 100).round(1),
        false_positives: fps,
        precision: flagged.zero? ? 0.0 : (caught.to_f / flagged * 100).round(1),
        type_errors: results.sum { it[:type_errors] },
        ambiguous: results.sum { (it[:ambiguous] || []).size }
      }
    )
  end

  # Recall by PII type, across all documents.
  def by_pii_type(results)
    results.flat_map { it[:detail] }
           .group_by { it[:type] }
           .transform_values do |items|
             { planted: items.size,
               caught: items.count { it[:caught] },
               recall: (items.count { it[:caught] }.to_f / items.size * 100).round(1) }
           end
  end
end
