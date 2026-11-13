# frozen_string_literal: true

require "bigdecimal"

module MoneyCents
  module_function

  # Convert a dollar amount (Numeric or String) to integer cents, half-up.
  def round_dollars(amount)
    scaled = (BigDecimal(amount.to_s) * 100)
    scaled.round(0, BigDecimal::ROUND_HALF_UP).to_i
  end
end
