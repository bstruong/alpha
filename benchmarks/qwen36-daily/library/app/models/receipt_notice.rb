class ReceiptNotice
  def self.deliveries
    @deliveries ||= []
  end

  def self.deliver(receipt)
    deliveries << receipt.id
  end

  def self.reset!
    @deliveries = []
  end
end
