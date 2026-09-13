class ProcessPaymentEventJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  OUTCOME_BY_EVENT_TYPE = {
    "payment.succeeded" => "succeeded",
    "payment.failed"    => "failed"
  }.freeze

  def perform(payment_event_id)
    event = PaymentEvent.find(payment_event_id)

    claimed = event.with_lock do
      if event.status == "received"
        event.update!(status: "processing")
        true
      else
        false
      end
    end
    return unless claimed

    outcome = OUTCOME_BY_EVENT_TYPE[event.event_type]
    if outcome.nil?
      Rails.logger.info("[process] event=#{event.id} type=#{event.event_type} not actionable")
      return event.update!(status: "ignored")
    end

    reference = event.payload["provider_reference_id"]
    txn = Transaction.find_by(provider_reference_id: reference)

    if txn.nil?
      Rails.logger.error("[process] event=#{event.id} orphaned reference=#{reference.inspect}")
      return event.update!(status: "orphaned")
    end

    event.update!(transaction_id: txn.id)

    ResolveTransaction.call(txn: txn, outcome: outcome, source: :webhook)

    event.update!(status: "processed", processed_at: Time.current)
  end
end