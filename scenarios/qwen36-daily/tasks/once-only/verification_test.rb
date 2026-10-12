require "test_helper"

class VerifierTest < ActiveSupport::TestCase
  setup do
    ReceiptNotice.reset!
    @account = Account.create!(name: "Ada", email: "ada-once@example.com")
    @row = { account: @account, amount: "4.00", key: "order-9" }
  end

  test "a retry after commit sends one receipt" do
    ReceiptBatch.deliver([ @row ])
    ReceiptBatch.deliver([ @row ])

    assert_equal 1, Receipt.where(idempotency_key: "order-9").count
    assert_equal 1, ReceiptNotice.deliveries.size
  end

  test "a crash after the receipt is claimed does not send a second notice" do
    ReceiptBatch.deliver([ @row ])
    ReceiptNotice.reset!
    receipt = Receipt.find_by!(idempotency_key: "order-9")
    receipt.update_columns(sent_at: nil, claimed_at: Time.current)

    ReceiptBatch.deliver([ @row ])

    assert_empty ReceiptNotice.deliveries
  end

  test "an empty batch does not raise" do
    assert_nothing_raised { ReceiptBatch.deliver([]) }
    assert_empty ReceiptNotice.deliveries
  end
end
