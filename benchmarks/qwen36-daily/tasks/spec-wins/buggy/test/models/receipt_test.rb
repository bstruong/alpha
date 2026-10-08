require "test_helper"

class ReceiptTest < ActiveSupport::TestCase
  test "two tenths make three tenths" do
    total = Receipt.quote("0.1", "0.2")

    assert_in_delta 0.3, total, 0.0001
  end

  test "a batch of one stores a receipt" do
    account = Account.create!(name: "Ada", email: "ada-receipt@example.com")
    ReceiptNotice.reset!

    ReceiptBatch.deliver([ { account: account, amount: "4.00", key: "order-1" } ])

    assert_equal 1, Receipt.where(idempotency_key: "order-1").count
  end
end
