require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  setup do
    purge_payment_data!
    @customer = Customer.create!(email: "model@example.com")
    @order    = @customer.orders.create!(amount_cents: 10_000)
  end

  test "provider_reference_id must be unique" do
    @order.transactions.create!(provider_reference_id: "ref_dup", amount_cents: 10_000)
    duplicate = @order.transactions.build(provider_reference_id: "ref_dup", amount_cents: 10_000)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:provider_reference_id, :taken)
  end

  test "new payments start pending and unresolved" do
    txn = @order.transactions.create!(provider_reference_id: "ref_new", amount_cents: 10_000)

    assert_equal "pending", txn.status
    assert_nil txn.resolved_at
    assert_nil txn.resolved_by
  end

  test "stale scope returns only pending payments older than the cutoff" do
    fresh = @order.transactions.create!(provider_reference_id: "ref_fresh", amount_cents: 10_000)
    old   = @order.transactions.create!(provider_reference_id: "ref_old", amount_cents: 10_000)
    old.update_column(:created_at, 1.hour.ago)
    settled = @order.transactions.create!(provider_reference_id: "ref_settled", amount_cents: 10_000)
    settled.update_columns(created_at: 1.hour.ago, status: "succeeded")

    stale = Transaction.stale(15.minutes)

    assert_includes     stale, old
    assert_not_includes stale, fresh,   "fresh payments may still be in flight"
    assert_not_includes stale, settled, "settled payments need no reconciliation"
  end
end
