require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "accepts a new event and enqueues processing" do
    assert_enqueued_with(job: ProcessPaymentEventJob) do
      post "/webhooks/payments", params: { event_id: "evt_new_unique_123", event_type: "payment.succeeded" }
    end
    assert_response :accepted
    assert PaymentEvent.exists?(event_id: "evt_new_unique_123")
  end

  test "ignores a duplicate and enqueues nothing" do
    existing = payment_events(:succeeded_event)
    assert_no_enqueued_jobs do
      post "/webhooks/payments", params: { event_id: existing.event_id, event_type: existing.event_type }
    end
    assert_response :ok
    assert_equal "duplicate_ignored", JSON.parse(response.body)["status"]
  end

  test "rejects a request missing event_id" do
    post "/webhooks/payments", params: { event_type: "payment.succeeded" }
    assert_response :bad_request
  end
end