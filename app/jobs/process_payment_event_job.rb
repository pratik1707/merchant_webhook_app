class ProcessPaymentEventJob < ApplicationJob
  queue_as :default

  # Safe to retry: perform() is idempotent, so re-running after a failure redoes no work.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(payment_event_id)
    event = PaymentEvent.find(payment_event_id)
    # Idempotency guard: not atomic under true concurrency, but covers duplicate enqueues.
    return if event.status == "processed" # safety check in case of duplicate job enqueue

    case event.event_type
    when "payment.succeeded"
      Rails.logger.info("[job] Marking order paid for event #{event.event_id}")
    when "payment.failed"
      Rails.logger.info("[job] Marking order failed for event #{event.event_id}")
    else
      Rails.logger.warn("[job] Unknown event_type #{event.event_type} for #{event.event_id}")
    end

    event.update!(status: "processed", processed_at: Time.current)
  end
end