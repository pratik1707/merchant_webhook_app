require "test_helper"

class ProcessPaymentEventJobTest < ActiveJob::TestCase
  test "marks a received event as processed" do
    event = payment_events(:pending_event)
    ProcessPaymentEventJob.perform_now(event.id)
    event.reload
    assert_equal "processed", event.status
    assert_not_nil event.processed_at
  end

  test "is safe to run twice on the same event" do
    event = payment_events(:pending_event)
    ProcessPaymentEventJob.perform_now(event.id)
    ProcessPaymentEventJob.perform_now(event.id)
    event.reload
    assert_equal "processed", event.status
  end
end