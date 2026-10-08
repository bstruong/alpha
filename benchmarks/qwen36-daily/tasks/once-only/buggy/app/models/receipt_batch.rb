class ReceiptBatch
  def self.deliver(rows)
    raise ArgumentError, "nothing to send" if rows.empty?

    rows.each do |row|
      receipt = Receipt.create!(
        account: row.fetch(:account),
        amount: row.fetch(:amount),
        idempotency_key: row.fetch(:key)
      )
      ReceiptNotice.deliver(receipt)
      receipt.update_column(:sent_at, Time.current)
    end
  end
end
