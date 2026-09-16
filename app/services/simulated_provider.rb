
class SimulatedProvider
  EVENT_TYPE = { "succeeded" => "payment.succeeded", "failed" => "payment.failed" }.freeze

  def self.charge!(reference_id:, amount_cents:, idempotency_key: nil,
                   drop_webhook: false, fail_charge: false)
    status = fail_charge ? "failed" : "succeeded"

    charge = ProviderCharge.find_or_create_by!(reference_id: idempotency_key || reference_id) do |c|
      c.amount_cents = amount_cents
      c.status       = status
    end

    return :webhook_dropped if drop_webhook

    # In production the provider POSTs this to WebhooksController over HTTP.
    IngestWebhookEvent.call(
      event_id:   "evt_#{SecureRandom.hex(8)}",
      event_type: EVENT_TYPE.fetch(charge.status),
      payload:    { "provider_reference_id" => reference_id, "amount_cents" => amount_cents }
    )
    :webhook_delivered
  end

  # What reconciliation calls. nil means the provider has no outcome yet.
  def self.status_for(reference_id)
    ProviderCharge.find_by(reference_id: reference_id)&.status
  end
end
