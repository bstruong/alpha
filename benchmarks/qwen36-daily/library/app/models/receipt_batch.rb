class ReceiptBatch
  def self.deliver(rows)
    rows.each do |row|
      next if Receipt.exists?(idempotency_key: row.fetch(:key))

      Receipt.create!(
        account: row.fetch(:account),
        amount: row.fetch(:amount),
        idempotency_key: row.fetch(:key)
      )
    end
  end
end
