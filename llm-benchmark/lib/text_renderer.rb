# frozen_string_literal: true

# Renders a Statement value object into statement-like plain text — the
# `source.txt` the model reads. Three layout styles exercise different
# extraction difficulties:
#   :clean   — aligned columns, ISO-ish dates (easy)
#   :compact — different bank's format, US dates, $ signs (medium)
#   :messy   — wrapped descriptions, footnotes, inconsistent spacing (hard)
#
# Strategy as a callable (Olsen) — each style is just a private method
# selected by name; no subclass hierarchy needed.
class TextRenderer
  STYLES = %i[clean compact messy].freeze

  def initialize(style:)
    raise ArgumentError, "unknown style: #{style}" unless STYLES.include?(style)

    @style = style
  end

  def render(statement)
    send(@style, statement)
  end

  private

  def clean(statement)
    lines = []
    lines << StatementGenerator::INSTITUTIONS.fetch(statement.institution_slug).upcase
    lines << "Statement Period: #{iso(statement.period_start)} to #{iso(statement.period_end)}"
    lines << "Account #{statement.account_kind.tr('_', ' ').capitalize} ****#{statement.account_number_last_four}"
    lines << ""
    lines << "Beginning Balance: #{dollars(statement.beginning_balance_cents)}"
    lines << ""
    lines << format("%-12s %-32s %14s %16s", "Date", "Description", "Amount", "Balance")

    running = statement.beginning_balance_cents
    statement.transactions.each do |txn|
      running += txn.amount_cents
      lines << format(
        "%-12s %-32s %14s %16s",
        iso(txn.posted_at), txn.description, signed_dollars(txn.amount_cents), dollars(running)
      )
    end

    lines << ""
    lines << "Ending Balance: #{dollars(statement.ending_balance_cents)}"
    lines.join("\n")
  end

  def compact(statement)
    lines = []
    lines << "#{StatementGenerator::INSTITUTIONS.fetch(statement.institution_slug)} | Acct ...#{statement.account_number_last_four}"
    lines << "Period #{us(statement.period_start)} - #{us(statement.period_end)}"
    lines << "Opening balance #{dollars(statement.beginning_balance_cents)}"
    statement.transactions.each do |txn|
      lines << "#{us(txn.posted_at)}  #{txn.description}  #{signed_dollars(txn.amount_cents)}"
    end
    lines << "Closing balance #{dollars(statement.ending_balance_cents)}"
    lines.join("\n")
  end

  def messy(statement)
    lines = []
    lines << "  #{StatementGenerator::INSTITUTIONS.fetch(statement.institution_slug).upcase}  "
    lines << "  ---------------------------------------------"
    lines << "  For the period #{long_date(statement.period_start)} through"
    lines << "  #{long_date(statement.period_end)}"
    lines << "  Account ending in #{statement.account_number_last_four}*"
    lines << ""
    lines << "  Balance forward .......... #{dollars(statement.beginning_balance_cents)}"
    lines << ""

    statement.transactions.each_with_index do |txn, index|
      # Wrap some descriptions across lines to simulate real-world noise.
      if index.odd? && txn.description.length > 12
        head, tail = txn.description.split(" ", 2)
        lines << "  #{us(txn.posted_at)}   #{head}"
        lines << "             #{tail}        #{signed_dollars(txn.amount_cents)}"
      else
        lines << "  #{us(txn.posted_at)}   #{txn.description}     #{signed_dollars(txn.amount_cents)}"
      end
    end

    lines << ""
    lines << "  Ending balance ........... #{dollars(statement.ending_balance_cents)}"
    lines << "  * Last four digits shown for security."
    lines << "  Member FDIC. This is not a bill."
    lines.join("\n")
  end

  # --- formatting helpers ---

  def iso(date)
    date.strftime("%Y-%m-%d")
  end

  def us(date)
    date.strftime("%m/%d/%Y")
  end

  def long_date(date)
    date.strftime("%B %-d, %Y")
  end

  def dollars(cents)
    format("$%.2f", cents / 100.0)
  end

  def signed_dollars(cents)
    sign = cents.negative? ? "-" : "+"
    "#{sign}#{format('$%.2f', cents.abs / 100.0)}"
  end
end
