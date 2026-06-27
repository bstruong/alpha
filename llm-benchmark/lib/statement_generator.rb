# frozen_string_literal: true

require "date"
require_relative "statement"

# Generates synthetic Statement value objects. Deterministic given a seed,
# so a fixture set is reproducible. Produces the *truth* — renderers turn
# that truth into statement-like text; the truth itself is the answer key.
class StatementGenerator
  # Single Responsibility — only constructs Statement objects.

  INSTITUTIONS = {
    "chase" => "Chase",
    "schwab" => "Charles Schwab",
    "bofa" => "Bank of America"
  }.freeze

  DEPOSIT_DESCRIPTIONS = [
    "Payroll deposit", "ACH credit - Employer", "Mobile check deposit",
    "Interest payment", "Refund - Online retailer", "Zelle from J. Doe"
  ].freeze

  WITHDRAWAL_DESCRIPTIONS = [
    "Whole Foods Market", "PG&E utility bill", "Mortgage payment - ACH",
    "Comcast internet", "Shell gas station", "Amazon Marketplace",
    "Spotify subscription", "Transfer to savings", "ATM withdrawal"
  ].freeze

  BROKERAGE_DESCRIPTIONS = [
    "Buy 10 VOO @ market", "Sell 5 AAPL @ limit", "Dividend - VTI",
    "Reinvested dividend", "Cash sweep interest", "Wire transfer in"
  ].freeze

  def initialize(seed: nil)
    @random = seed ? Random.new(seed) : Random.new
  end

  # Returns a Statement. kind: :bank or :brokerage.
  def generate(institution_slug:, kind:, year:, month:)
    period_start = Date.new(year, month, 1)
    period_end = Date.new(year, month, -1)
    beginning = random_cents(min: 100_00, max: 500_000_00)

    Statement.new(
      institution_slug: institution_slug,
      account_number_last_four: format("%04d", random.rand(0..9999)),
      account_kind: account_kind_for(kind),
      period_start: period_start,
      period_end: period_end,
      beginning_balance_cents: beginning,
      transactions: build_transactions(period_start, period_end, kind)
    )
  end

  private

  attr_reader :random

  def account_kind_for(kind)
    kind == :brokerage ? "brokerage" : %w[bank_checking bank_savings].sample(random: random)
  end

  def build_transactions(period_start, period_end, kind)
    count = random.rand(8..24)
    days = (period_end - period_start).to_i

    # Guard clause — sort by date so the rendered statement reads naturally.
    Array.new(count) { build_transaction(period_start, days, kind) }
      .sort_by(&:posted_at)
  end

  def build_transaction(period_start, days, kind)
    posted_at = period_start + random.rand(0..days)
    deposit = random.rand < 0.35

    Transaction.new(
      posted_at: posted_at,
      description: description_for(kind, deposit),
      amount_cents: amount_for(deposit),
      kind: transaction_kind(kind, deposit)
    )
  end

  def description_for(kind, deposit)
    pool =
      if kind == :brokerage
        BROKERAGE_DESCRIPTIONS
      elsif deposit
        DEPOSIT_DESCRIPTIONS
      else
        WITHDRAWAL_DESCRIPTIONS
      end
    pool.sample(random: random)
  end

  def amount_for(deposit)
    magnitude = random_cents(min: 1_00, max: 5_000_00)
    deposit ? magnitude : -magnitude
  end

  def transaction_kind(kind, deposit)
    return "trade" if kind == :brokerage
    deposit ? "deposit" : "withdrawal"
  end

  def random_cents(min:, max:)
    random.rand(min..max)
  end
end
