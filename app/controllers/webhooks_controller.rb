class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  def payments
    event_id   = params[:event_id]
    event_type = params[:event_type]

    if event_id.blank? || event_type.blank?
      return render json: { error: "event_id and event_type are required" }, status: :bad_request
    end

    # Idempotency + concurrency: relies on a unique DB index on event_id, not app logic -
    # so even two simultaneous duplicate webhooks can't both create a row.
    event = nil
    ActiveRecord::Base.transaction do
      event = PaymentEvent.create!(
        event_id: event_id,
        event_type: event_type,
        payload: params.to_unsafe_h
      )
    end

    ProcessPaymentEventJob.perform_later(event.id)
    render json: { status: "accepted", event_id: event_id }, status: :accepted

  # Duplicate delivery lands here instead of creating a second row; return 200 so the
  # sender doesn't retry again.
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.info("[webhook] Ignored DUPLICATE event #{event_id}: #{e.class}")
    render json: { status: "duplicate_ignored", event_id: event_id }, status: :ok
  end
end