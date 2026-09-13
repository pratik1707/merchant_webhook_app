require "test_helper"

class ReconcileStaleTransactionsJobTest < ActiveSupport::TestCase
  setup do
    purge_payment_data!
    @customer = Customer.create!(email: "reconcile@example.com")
  end

  test "recovers a payment whose webhook was dropped" do
    txn = initiate_payment!(customer: @customer, drop_webhook: true)

    # nothing arrived, so nothing moved - the invisible failure
    assert_equal "pending", txn.reload.status
    assert_equal 0, PaymentEvent.count

    age!(txn)
    stats = ReconcileStaleTransactionsJob.new.perform

    assert_equal "succeeded",      txn.reload.status
    assert_equal "reconciliation", txn.resolved_by
    assert_equal "paid",           txn.order.reload.status
    assert_equal 1, stats[:checked]
    assert_equal 1, stats[:resolved]
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end

  test "ignores payments that are not stale yet" do
    txn = initiate_payment!(customer: @customer, drop_webhook: true)

    stats = ReconcileStaleTransactionsJob.new.perform

    assert_equal 0, stats[:checked], "a fresh pending payment may still be in flight"
    assert_equal "pending", txn.reload.status
  end

  test "leaves a payment pending when the provider has no outcome yet" do
    order = @customer.orders.create!(amount_cents: 10_000)
    # deliberately never charged: provider has no record, like an ACH debit still clearing
    txn = order.transactions.create!(provider_reference_id: "ref_inflight", amount_cents: 10_000)
    age!(txn)

    stats = ReconcileStaleTransactionsJob.new.perform

    assert_equal 1, stats[:checked]
    assert_equal 1, stats[:still_pending]
    assert_equal "pending", txn.reload.status
  end

  test "recovers a failed payment without fulfilling" do
    txn = initiate_payment!(customer: @customer, drop_webhook: true, fail_charge: true)
    age!(txn)

    ReconcileStaleTransactionsJob.new.perform

    assert_equal "failed", txn.reload.status
    assert_equal "failed", txn.order.reload.status
    assert_enqueued_jobs 0, only: FulfillOrderJob
  end

  test "running twice does not fulfill twice" do
    txn = initiate_payment!(customer: @customer, drop_webhook: true)
    age!(txn)

    ReconcileStaleTransactionsJob.new.perform
    second = ReconcileStaleTransactionsJob.new.perform

    assert_equal 0, second[:checked], "resolved payments are no longer pending"
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end

  test "a late webhook arriving after reconciliation is a no-op" do
    txn = initiate_payment!(customer: @customer, drop_webhook: true)
    age!(txn)
    ReconcileStaleTransactionsJob.new.perform

    # the dropped webhook finally shows up
    deliver_webhook!(event_id: "evt_late_delivery",
                     event_type: "payment.succeeded",
                     reference_id: txn.provider_reference_id)

    assert_equal "reconciliation", txn.reload.resolved_by
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end

  test "reconciles a mixed batch and reports accurate counts" do
    3.times { initiate_payment!(customer: @customer) }
    dropped = 2.times.map { initiate_payment!(customer: @customer, drop_webhook: true) }

    assert_equal 3, Transaction.succeeded.count
    assert_equal 2, Transaction.pending.count

    dropped.each { |t| age!(t) }
    stats = ReconcileStaleTransactionsJob.new.perform

    assert_equal 2, stats[:checked]
    assert_equal 2, stats[:resolved]
    assert_equal 5, Transaction.succeeded.count
    assert_equal 0, Transaction.pending.count
    assert_equal({ "webhook" => 3, "reconciliation" => 2 },
                 Transaction.succeeded.group(:resolved_by).count)
  end
end
