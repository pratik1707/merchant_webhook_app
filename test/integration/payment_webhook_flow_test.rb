require "test_helper"

class PaymentWebhookFlowTest < ActionDispatch::IntegrationTest
  setup do
    purge_payment_data!
    @customer = Customer.create!(email: "flow@example.com")
    @order    = @customer.orders.create!(amount_cents: 10_000)
    @txn      = @order.transactions.create!(provider_reference_id: "ref_flow",
                                            amount_cents: 10_000)
  end

  test "full flow: new event is accepted, processed, and duplicates are rejected" do
    deliver!(event_id: "evt_flow_1")

    assert_response :success
    event = PaymentEvent.find_by!(event_id: "evt_flow_1")
    assert_equal "processed", event.status
    assert_not_nil event.processed_at
    assert_equal @txn.id, event.transaction_id

    # and the payment itself is resolved
    assert_equal "succeeded", @txn.reload.status
    assert_equal "webhook",   @txn.resolved_by
    assert_equal "paid",      @order.reload.status
    assert_enqueued_jobs 1, only: FulfillOrderJob

    # same event again -> 200, but no second row and no second shipment
    deliver!(event_id: "evt_flow_1")

    assert_response :success
    assert_match(/duplicate_ignored/, response.body)
    assert_equal 1, PaymentEvent.where(event_id: "evt_flow_1").count
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end

  test "full flow: two different events are both processed independently" do

    deliver!(event_id: "evt_charge_succeeded")
    deliver!(event_id: "evt_payment_intent_succeeded")

    assert_equal 2, PaymentEvent.count, "both events are stored - they are genuinely different"
    assert_equal %w[processed processed],
                 PaymentEvent.order(:event_id).pluck(:status),
                 "each event is processed on its own merits"

    # ...but the payment is decided once, and the order ships once
    assert_equal "succeeded", @txn.reload.status
    assert_equal "paid",      @order.reload.status
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end

  test "idempotency: same payment.succeeded event delivered twice end-to-end" do
    3.times { deliver!(event_id: "evt_retry_me") }

    assert_equal 1, PaymentEvent.where(event_id: "evt_retry_me").count
    assert_equal "processed", PaymentEvent.find_by!(event_id: "evt_retry_me").status
    assert_equal "succeeded", @txn.reload.status
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end

  test "a payment.failed event fails the order and ships nothing" do
    deliver!(event_id: "evt_failed", event_type: "payment.failed")

    assert_equal "processed", PaymentEvent.find_by!(event_id: "evt_failed").status
    assert_equal "failed", @txn.reload.status
    assert_equal "failed", @order.reload.status
    assert_enqueued_jobs 0, only: FulfillOrderJob
  end

  test "an event referencing an unknown payment is marked orphaned, not silently dropped" do
    deliver!(event_id: "evt_orphan", reference_id: "ref_does_not_exist")

    assert_response :success
    event = PaymentEvent.find_by!(event_id: "evt_orphan")
    assert_equal "orphaned", event.status
    assert_nil event.processed_at
    assert_equal "pending", @txn.reload.status
    assert_enqueued_jobs 0, only: FulfillOrderJob
  end

  test "an event type we do not act on is ignored, leaving the payment alone" do
    deliver!(event_id: "evt_created", event_type: "payment.created")

    assert_equal "ignored", PaymentEvent.find_by!(event_id: "evt_created").status
    assert_equal "pending", @txn.reload.status
    assert_enqueued_jobs 0, only: FulfillOrderJob
  end

  test "a request without event_id is rejected and stores nothing" do
    post "/webhooks/payments", params: { event_type: "payment.succeeded" }

    assert response.client_error?, "expected a 4xx, got #{response.status}"
    assert_equal 0, PaymentEvent.count
  end

  private

  # Posts a webhook and runs the processing job inline, leaving FulfillOrderJob
  # enqueued so tests can count shipments.
  def deliver!(event_id:, event_type: "payment.succeeded", reference_id: nil)
    perform_enqueued_jobs(only: ProcessPaymentEventJob) do
      post "/webhooks/payments", params: {
        event_id:              event_id,
        event_type:            event_type,
        provider_reference_id: reference_id || @txn.provider_reference_id
      }
    end
  end
end