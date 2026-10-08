class Receipt < ApplicationRecord
  belongs_to :account

  def self.quote(first, second)
    BigDecimal(first.to_s) + BigDecimal(second.to_s)
  end

  def send_notice
    return if claimed_at.present? || sent_at.present?

    update_column(:claimed_at, Time.current)
    ReceiptNotice.deliver(self)
    update_column(:sent_at, Time.current)
  end
end
