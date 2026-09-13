class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  # Fields we trust enough to persist from the raw webhook body.
  # Adjust this list to match your actual payment provider's payload schema.
  PERMITTED_PAYLOAD_FIELDS = %w[provider_reference_id amount_cents currency].freeze

  def payments
    return render json: { error: "event_id and event_type are required" }, status: :bad_request if params[:event_id].blank? || params[:event_type].blank?

    event = PaymentEvent.create!(
      event_id: params[:event_id],
      event_type: params[:event_type],
      payload: permitted_payload
    )

    ProcessPaymentEventJob.perform_later(event.id)
    render json: { status: "accepted", event_id: event.event_id }, status: :accepted
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    # Unique index on event_id is the real idempotency guarantee - this just
    # tells the sender "got it" instead of triggering another retry.
    Rails.logger.info("[webhook] duplicate event=#{params[:event_id]} (#{e.class})")
    render json: { status: "duplicate_ignored", event_id: params[:event_id] }, status: :ok
  end

  private

  def permitted_payload
    params.permit(*PERMITTED_PAYLOAD_FIELDS).to_h
  end
end