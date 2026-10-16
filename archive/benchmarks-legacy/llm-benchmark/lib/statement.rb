# frozen_string_literal: true

# Value objects representing the canonical truth of a statement.
# The generator produces these; renderers and the scorer consume them.
# Money is always integer cents — never floats (mirrors ASSASSIN).

# A single transaction. amount_cents is signed: deposits positive,
# withdrawals/fees negative.
Transaction = Data.define(:posted_at, :description, :amount_cents, :kind) do
  # Tell, don't ask — the object reports its own direction.
  def deposit?
    amount_cents.positive?
  end

  def to_h
    {
      "posted_at" => posted_at.to_s,
      "description" => description,
      "amount_cents" => amount_cents,
      "transaction_kind_hint" => kind
    }
  end
end

# A full statement. ending_balance is derived, never stored independently,
# so the answer key is always internally consistent.
Statement = Data.define(
  :institution_slug,
  :account_number_last_four,
  :account_kind,
  :period_start,
  :period_end,
  :beginning_balance_cents,
  :transactions
) do
  def ending_balance_cents
    beginning_balance_cents + transactions.sum(&:amount_cents)
  end

  def total_deposits_cents
    transactions.select(&:deposit?).sum(&:amount_cents)
  end

  def total_withdrawals_cents
    transactions.reject(&:deposit?).sum(&:amount_cents)
  end

  # The canonical answer key. This is what model output is scored against.
  def to_expected_json
    {
      "institution_slug" => institution_slug,
      "account_number_last_four" => account_number_last_four,
      "period_start" => period_start.to_s,
      "period_end" => period_end.to_s,
      "beginning_balance_cents" => beginning_balance_cents,
      "ending_balance_cents" => ending_balance_cents,
      "transactions" => transactions.map(&:to_h)
    }
  end
end
