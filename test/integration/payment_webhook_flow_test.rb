require "test_helper"

class PaymentWebhookFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "full flow: new event is accepted, processed, and duplicates are rejected" do
    event_id = "evt_flow_test_#{SecureRandom.hex(4)}"

    # Step 1: the webhook arrives for the first time
    assert_enqueued_with(job: ProcessPaymentEventJob) do
      post "/webhooks/payments", params: { event_id: event_id, event_type: "payment.succeeded" }
    end
    assert_response :accepted
    assert_equal "accepted", JSON.parse(response.body)["status"]

    event = PaymentEvent.find_by(event_id: event_id)
    assert_not_nil event
    assert_equal "received", event.status
    assert_nil event.processed_at

    # Step 2: the background worker actually runs the queued job
    perform_enqueued_jobs

    event.reload
    assert_equal "processed", event.status
    assert_not_nil event.processed_at

    # Step 3: the provider retries and sends the SAME event again (duplicate delivery)
    assert_no_enqueued_jobs do
      post "/webhooks/payments", params: { event_id: event_id, event_type: "payment.succeeded" }
    end
    assert_response :ok
    assert_equal "duplicate_ignored", JSON.parse(response.body)["status"]

    # Step 4: prove no double-processing happened -- exactly one row, still processed once
    assert_equal 1, PaymentEvent.where(event_id: event_id).count
    event.reload
    assert_equal "processed", event.status

    # Step 5: even a THIRD duplicate delivery (e.g. provider retries again later) is still safe
    post "/webhooks/payments", params: { event_id: event_id, event_type: "payment.succeeded" }
    assert_response :ok
    assert_equal 1, PaymentEvent.where(event_id: event_id).count
  end

  test "full flow: two different events are both processed independently" do
    event_a = "evt_flow_a_#{SecureRandom.hex(4)}"
    event_b = "evt_flow_b_#{SecureRandom.hex(4)}"

    perform_enqueued_jobs do
      post "/webhooks/payments", params: { event_id: event_a, event_type: "payment.succeeded" }
      post "/webhooks/payments", params: { event_id: event_b, event_type: "payment.failed" }
    end

    assert_equal "processed", PaymentEvent.find_by(event_id: event_a).status
    assert_equal "processed", PaymentEvent.find_by(event_id: event_b).status
    assert_equal 2, PaymentEvent.where(event_id: [event_a, event_b]).count
  end

    test "idempotency: same payment.succeeded event delivered twice end-to-end" do
    event_id = "evt_idempotent_#{SecureRandom.hex(4)}"

    # First delivery: provider sends payment.succeeded
    perform_enqueued_jobs do
      post "/webhooks/payments", params: { event_id: event_id, event_type: "payment.succeeded" }
    end
    assert_response :accepted
    assert_equal "accepted", JSON.parse(response.body)["status"]

    first_event = PaymentEvent.find_by(event_id: event_id)
    assert_equal "processed", first_event.status
    first_processed_at = first_event.processed_at
    assert_not_nil first_processed_at

    # Second delivery: EXACT same event_id and event_type (provider retried the same webhook)
    assert_no_enqueued_jobs do
      post "/webhooks/payments", params: { event_id: event_id, event_type: "payment.succeeded" }
    end
    assert_response :ok
    assert_equal "duplicate_ignored", JSON.parse(response.body)["status"]

    # Prove: still exactly one row, still processed, and processed_at did NOT change
    # (i.e. it wasn't silently reprocessed)
    assert_equal 1, PaymentEvent.where(event_id: event_id).count
    second_event = PaymentEvent.find_by(event_id: event_id)
    assert_equal "processed", second_event.status
    assert_equal first_processed_at, second_event.processed_at

    # Prove the audit trail (paper_trail) only recorded the ONE create + ONE update --
    # the duplicate delivery left no trace of a second processing attempt
    assert_equal 2, second_event.versions.count
  end
end