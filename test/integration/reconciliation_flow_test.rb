require "test_helper"

class ReconciliationFlowTest < ActionDispatch::IntegrationTest
  setup do
    purge_payment_data!
    @customer = Customer.create!(email: "flow@example.com")
  end

  test "happy path: the webhook resolves the payment" do
    txn = initiate_payment!(customer: @customer)

    assert_equal "succeeded", txn.reload.status
    assert_equal "webhook",   txn.resolved_by
    assert_equal "paid",      txn.order.reload.status

    event = PaymentEvent.last
    assert_equal "processed", event.status
    assert_equal txn.id,      event.transaction_id
  end

  # THE important one: two DIFFERENT event ids for one payment. A unique index on
  # event_id cannot catch this (both events are genuinely new), so the transition
  # guard is what prevents shipping twice.
  test "two different events for the same payment resolve it only once" do
    txn = initiate_payment!(customer: @customer, drop_webhook: true)

    %w[evt_charge_succeeded evt_payment_intent_succeeded].each do |event_id|
      deliver_webhook!(event_id: event_id,
                       event_type: "payment.succeeded",
                       reference_id: txn.provider_reference_id)
    end

    assert_equal 2, PaymentEvent.count, "both events stored - correctly, they are different"
    assert_equal "succeeded", txn.reload.status
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end

  test "a duplicate delivery of the same event id is ignored" do
    txn = initiate_payment!(customer: @customer, drop_webhook: true)

    deliver_webhook!(event_id: "evt_same", event_type: "payment.succeeded",
                     reference_id: txn.provider_reference_id)
    result = IngestWebhookEvent.call(
      event_id:   "evt_same",
      event_type: "payment.succeeded",
      payload:    { "provider_reference_id" => txn.provider_reference_id }
    )

    assert_equal :duplicate_ignored, result.status
    assert_equal 1, PaymentEvent.where(event_id: "evt_same").count
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end

  test "an event for an unknown reference is marked orphaned, not silently dropped" do
    deliver_webhook!(event_id: "evt_orphan", event_type: "payment.succeeded",
                     reference_id: "ref_does_not_exist")

    assert_equal "orphaned", PaymentEvent.find_by(event_id: "evt_orphan").status
    assert_enqueued_jobs 0, only: FulfillOrderJob
  end

  test "an event type we do not act on is ignored" do
    txn = initiate_payment!(customer: @customer, drop_webhook: true)

    deliver_webhook!(event_id: "evt_created", event_type: "payment.created",
                     reference_id: txn.provider_reference_id)

    assert_equal "ignored", PaymentEvent.find_by(event_id: "evt_created").status
    assert_equal "pending", txn.reload.status
  end

  # Reconciliation has no way to know a webhook was actually LOST versus just
  # running behind schedule - it only knows the transaction is stale. So a webhook
  # that shows up after reconciliation already resolved the same transaction is not
  # an edge case, it's the expected case whenever the provider is slow rather than
  # silent. It has to be a no-op for the same reason two webhook events do: only one
  # writer may ever flip a transaction out of "pending".
  test "a webhook that arrives after reconciliation already resolved the same transaction is a no-op" do
    txn = initiate_payment!(customer: @customer, drop_webhook: true)
    age!(txn, by: ReconcileStaleTransactionsJob::STALE_AFTER + 1.minute)

    stats = ReconcileStaleTransactionsJob.new.perform
    assert_equal 1, stats[:resolved]

    assert_equal "succeeded",      txn.reload.status
    assert_equal "reconciliation", txn.resolved_by
    assert_equal "paid",           txn.order.reload.status
    assert_enqueued_jobs 1, only: FulfillOrderJob

    # The provider's webhook was never actually dropped - it was just slow. It shows
    # up now, for a transaction that isn't "pending" anymore.
    deliver_webhook!(event_id: "evt_late_arrival", event_type: "payment.succeeded",
                     reference_id: txn.provider_reference_id)

    assert_equal "processed", PaymentEvent.find_by(event_id: "evt_late_arrival").status
    assert_equal "reconciliation", txn.reload.resolved_by
    assert_equal "succeeded",      txn.status
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end
end