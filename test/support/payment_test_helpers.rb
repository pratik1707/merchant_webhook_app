class ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Fixtures would collide with the exact counts these tests assert on.
  def purge_payment_data!
    [PaymentEvent, Transaction, Order, Customer, ProviderCharge].each(&:delete_all)
  end

  # Runs the webhook-processing job inline (so the payment actually resolves) while
  # leaving FulfillOrderJob enqueued, so tests can count fulfillments.
  def initiate_payment!(customer:, amount_cents: 10_000, **opts)
    txn = nil
    perform_enqueued_jobs(only: ProcessPaymentEventJob) do
      txn = InitiatePayment.call(customer: customer, amount_cents: amount_cents, **opts)
    end
    txn
  end

  def deliver_webhook!(event_id:, event_type:, reference_id:)
    perform_enqueued_jobs(only: ProcessPaymentEventJob) do
      IngestWebhookEvent.call(
        event_id:   event_id,
        event_type: event_type,
        payload:    { "provider_reference_id" => reference_id }
      )
    end
  end

  def age!(txn, by: 1.hour)
    txn.update_column(:created_at, by.ago)
  end
end
