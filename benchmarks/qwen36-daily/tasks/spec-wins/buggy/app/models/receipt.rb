class Receipt < ApplicationRecord
  belongs_to :account

  after_commit :send_notice, on: :create

  def self.quote(first, second)
    first.to_f + second.to_f
  end

  def send_notice
    return if claimed_at.present? || sent_at.present?

    update_column(:claimed_at, Time.current)
    ReceiptNotice.deliver(self)
    update_column(:sent_at, Time.current)
  end
end
