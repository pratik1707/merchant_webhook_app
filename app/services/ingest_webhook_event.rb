# The single door every event comes through - live webhooks now, and any events
# pulled in by reconciliation later. One door means one set of protections.
class IngestWebhookEvent
  Result = Struct.new(:status, :payment_event, keyword_init: true)

  PERMITTED_PAYLOAD_FIELDS = %w[provider_reference_id amount_cents currency].freeze

  def self.call(event_id:, event_type:, payload: {})
    event = PaymentEvent.create!(
      event_id:   event_id,
      event_type: event_type,
      status:     "received",
      payload:    payload.to_h.stringify_keys.slice(*PERMITTED_PAYLOAD_FIELDS)
    )

    ProcessPaymentEventJob.perform_later(event.id)
    Result.new(status: :ingested, payment_event: event)
  rescue ActiveRecord::RecordNotUnique
    Result.new(status: :duplicate_ignored, payment_event: PaymentEvent.find_by(event_id: event_id))
  rescue ActiveRecord::RecordInvalid => e
    # Only a duplicate event_id is a "duplicate". Anything else is a real bug and
    # must not be swallowed as one.
    raise unless e.record.errors.of_kind?(:event_id, :taken)
    Result.new(status: :duplicate_ignored, payment_event: PaymentEvent.find_by(event_id: event_id))
  end
end
