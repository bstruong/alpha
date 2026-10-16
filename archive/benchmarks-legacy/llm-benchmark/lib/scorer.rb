# frozen_string_literal: true

# Scores one model extraction against the certified answer key. Scoring
# rules are fixed up front (see README) so results can't be massaged after
# the fact. Money is exact-match — a cents mismatch is a hard fail.
#
# Single Responsibility — only scores; does no I/O and no model calls.
class Scorer
  SCALAR_FIELDS = %w[
    institution_slug account_number_last_four
    period_start period_end
  ].freeze

  MONEY_FIELDS = %w[beginning_balance_cents ending_balance_cents].freeze

  # The grade for one (model, document) extraction.
  Score = Data.define(
    :json_valid,
    :field_accuracy,
    :money_exact,
    :txn_precision,
    :txn_recall
  ) do
    def to_h
      {
        json_valid: json_valid,
        field_accuracy: field_accuracy.round(3),
        money_exact: money_exact,
        txn_precision: txn_precision.round(3),
        txn_recall: txn_recall.round(3)
      }
    end
  end

  # expected: Hash (parsed expected.json). actual: Hash or nil.
  def score(expected:, actual:)
    # Guard clause — invalid JSON zeroes everything; nothing else to grade.
    return zero_score unless actual

    Score.new(
      json_valid: true,
      field_accuracy: scalar_accuracy(expected, actual),
      money_exact: money_exact?(expected, actual),
      txn_precision: transaction_precision(expected, actual),
      txn_recall: transaction_recall(expected, actual)
    )
  end

  private

  def zero_score
    Score.new(json_valid: false, field_accuracy: 0.0, money_exact: false,
              txn_precision: 0.0, txn_recall: 0.0)
  end

  def scalar_accuracy(expected, actual)
    hits = SCALAR_FIELDS.count { |field| expected[field].to_s == actual[field].to_s }
    hits.to_f / SCALAR_FIELDS.size
  end

  def money_exact?(expected, actual)
    MONEY_FIELDS.all? { |field| expected[field] == actual[field] }
  end

  def transaction_precision(expected, actual)
    extracted = actual_transactions(actual)
    return 0.0 if extracted.empty?

    correct = matched_count(expected, actual)
    correct.to_f / extracted.size
  end

  def transaction_recall(expected, actual)
    wanted = expected_transactions(expected)
    return 0.0 if wanted.empty?

    correct = matched_count(expected, actual)
    correct.to_f / wanted.size
  end

  # A transaction matches on date + signed amount only. BOTH description and
  # kind hint are excluded from the match key: they are free-text fields that
  # models phrase inconsistently (e.g. "debit"/"credit" vs the fixtures'
  # "withdrawal"/"deposit"), so including them would punish correct extractions.
  def matched_count(expected, actual)
    remaining = actual_transactions(actual).map { |t| match_key(t) }

    expected_transactions(expected).count do |txn|
      key = match_key(txn)
      index = remaining.index(key)
      remaining.delete_at(index) if index # consume — avoid double-counting
      !index.nil?
    end
  end

  def match_key(txn)
    [txn["posted_at"].to_s, txn["amount_cents"]]
  end

  def expected_transactions(expected)
    expected.fetch("transactions", [])
  end

  def actual_transactions(actual)
    value = actual["transactions"]
    value.is_a?(Array) ? value : []
  end
end
