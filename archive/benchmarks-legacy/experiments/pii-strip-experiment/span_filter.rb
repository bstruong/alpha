# frozen_string_literal: true

# Mechanical post-inference filter, recommended by Run 14.
#
# Run 14 found the model's dominant failure on clean input was echoing the
# *question* back as the *answer*: given an empty labelled form it returned
# "Social security number" as an ssn, and given a redaction decoy it returned the
# masks ("***", "[REDACTED]", "██████████") as the PII they conceal. 13 of those
# 14 clean-document false positives were marked high-confidence, so the model's
# own uncertainty signal is no help here. This filter is therefore mechanical and
# runs *after* inference — it never touches the prompt, schema, or confidence field.
#
# Two deliberately narrow rules. Both are pattern-based, not fuzzy:
#
#   1. LABEL ECHO   — the span IS a PII field label ("Full name", "Telephone",
#                     "Date of birth:"), not a value sitting near one. Matched
#                     against a closed list of labels and synonyms, case-
#                     insensitively, with an optional trailing colon and collapsed
#                     internal whitespace. Exact match only: "Full name" is
#                     dropped, "Full name: Jane Doe" is not.
#
#   2. MASK ECHO    — the span is entirely masking characters or a bracketed
#                     placeholder: runs of *, #, x/X, _, -, ., block and
#                     box-drawing glyphs, or [REDACTED]/[WITHHELD]/[REMOVED]-style
#                     tokens; also any span with no alphanumeric content at all.
#
# Bias is toward UNDER-matching. A filter that eats a genuinely short surname
# would defeat the purpose, so:
#   - the x/# repeat rule requires 3+ characters and no other letters, so real
#     names ("Xu", "Cox") and real values are never candidates;
#   - label matching is exact-string, never substring or prefix;
#   - nothing is dropped on length alone.
#
# Every drop is returned with a reason so the filter is auditable, not silent.

module SpanFilter
  # Canonical PII field labels and reasonable synonyms. Closed list on purpose.
  LABELS = [
    # name
    "name", "full name", "fullname", "first name", "given name", "last name",
    "surname", "family name", "middle name", "legal name", "contact name",
    "reporting party", "recipient", "employee", "client", "patient", "applicant",
    # dob
    "dob", "d.o.b", "date of birth", "birth date", "birthdate", "born",
    # ssn
    "ssn", "s.s.n", "social security", "social security number",
    "social security no", "national insurance number", "tax id",
    # email
    "email", "e-mail", "email address", "e-mail address", "electronic mail",
    # phone
    "phone", "telephone", "phone number", "telephone number", "mobile",
    "mobile number", "cell", "cell phone", "home phone", "work phone",
    "contact number", "contact on file", "direct line", "fax", "ext", "extension",
    # address
    "address", "mailing address", "home address", "street", "street address",
    "address of record", "city", "state", "zip", "zip code", "postcode",
    "postal code", "country", "city/state/zip"
  ].freeze

  # Bracketed placeholder tokens: [REDACTED], <withheld>, (removed), {n/a} …
  PLACEHOLDER_WORDS = %w[
    redacted withheld removed hidden masked confidential
    private restricted anonymised anonymized na n/a none tbd unknown
    signature\ removed identifying\ details\ removed
  ].freeze

  module_function

  def canonical_label(text)
    text.to_s.strip.downcase.sub(/:\s*\z/, "").gsub(/\s+/, " ")
  end

  # Rule 1 — the span IS a field label, exactly.
  def label_echo?(text)
    LABELS.include?(canonical_label(text))
  end

  # Rule 2 — the span is nothing but masking.
  def mask_echo?(text)
    s = text.to_s.strip
    return false if s.empty?

    # No alphanumeric content whatsoever (***, ---, ___, ██████, ▓▒░, ...).
    return true unless s.match?(/[[:alnum:]]/)

    # Bracketed / parenthesised placeholder: [REDACTED], <withheld>, (n/a)
    if (m = s.match(/\A[\[\(\<\{]\s*(.+?)\s*[\]\)\>\}]\z/))
      return true if PLACEHOLDER_WORDS.include?(m[1].downcase.gsub(/\s+/, " "))
    end
    # Bare placeholder word used as a mask token
    return true if PLACEHOLDER_WORDS.include?(s.downcase.gsub(/\s+/, " ")) && s.match?(/\A[A-Za-z\/ ]+\z/) && s.length > 2

    # Repeated single masking character used as a convention: xxxx, ####, XXXXXX.
    # Requires 3+ of one char and nothing else alphanumeric — so "Xu", "Cox",
    # "555" and real values can never qualify.
    return true if s.match?(/\A[\p{P}\p{S}\s]*([xX#])\1{2,}[\p{P}\p{S}\s]*\z/)

    # Mixed mask punctuation around repeated mask chars: ***-****, xxx-xx-xxxx
    stripped = s.gsub(/[\p{P}\p{S}\s]/, "")
    return true if !stripped.empty? && stripped.match?(/\A([xX#])\1*\z/) && stripped.length >= 3

    false
  end

  def reason_for(text)
    return :label_echo if label_echo?(text)
    return :mask_echo  if mask_echo?(text)

    nil
  end

  # findings: [{ "text" =>, "type" =>, "confidence" => }]
  # Returns [kept_findings, dropped_records] — never mutates the input.
  def apply(findings)
    kept = []
    dropped = []
    Array(findings).each do |f|
      reason = reason_for(f["text"])
      if reason
        dropped << { text: f["text"], type: f["type"], confidence: f["confidence"], reason: reason }
      else
        kept << f
      end
    end
    [ kept, dropped ]
  end
end
