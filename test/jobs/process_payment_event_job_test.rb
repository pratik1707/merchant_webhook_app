require "test_helper"

class ProcessPaymentEventJobTest < ActiveJob::TestCase
  setup do
    purge_payment_data!

    @customer = Customer.create!(email: "job@example.com")
    @order    = @customer.orders.create!(amount_cents: 10_000)
    @txn      = @order.transactions.create!(provider_reference_id: "ref_job",
                                            amount_cents: 10_000)
  end

  test "marks a received event as processed" do
    event = build_event

    ProcessPaymentEventJob.perform_now(event.id)

    event.reload
    assert_equal "processed", event.status
    assert_not_nil event.processed_at
  end

  test "is safe to run twice on the same event" do
    event = build_event

    ProcessPaymentEventJob.perform_now(event.id)
    ProcessPaymentEventJob.perform_now(event.id)

    assert_equal "processed", event.reload.status
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end

  test "resolves the referenced payment" do
    event = build_event

    ProcessPaymentEventJob.perform_now(event.id)

    assert_equal "succeeded", @txn.reload.status
    assert_equal "webhook",   @txn.resolved_by
    assert_equal "paid",      @order.reload.status
    assert_equal @txn.id,     event.reload.transaction_id
  end

  test "marks an event with no matching payment as orphaned" do
    event = build_event(reference_id: "ref_does_not_exist")

    ProcessPaymentEventJob.perform_now(event.id)

    event.reload
    assert_equal "orphaned", event.status
    assert_nil event.processed_at
    assert_equal "pending", @txn.reload.status
  end

  test "ignores an event type it does not act on" do
    event = build_event(event_type: "payment.created")

    ProcessPaymentEventJob.perform_now(event.id)

    assert_equal "ignored", event.reload.status
    assert_equal "pending", @txn.reload.status
  end

  private

  def build_event(event_id: "evt_#{SecureRandom.hex(4)}",
                  event_type: "payment.succeeded",
                  reference_id: nil)
    PaymentEvent.create!(
      event_id:   event_id,
      event_type: event_type,
      status:     "received",
      payload:    { "provider_reference_id" => reference_id || @txn.provider_reference_id }
    )
  end
end