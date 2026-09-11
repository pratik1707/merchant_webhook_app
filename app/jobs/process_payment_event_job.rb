class ProcessPaymentEventJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(payment_event_id)
    event = PaymentEvent.find(payment_event_id)

    # Row lock makes the check-and-update atomic, closing the race window
    # where two workers both see "received" before either writes "processed".
    event.with_lock do
      return if event.processed?

      handle(event)
      event.update!(status: :processed, processed_at: Time.current)
    end
  end

  private

  def handle(event)
    case event.event_type
    when "payment.succeeded" then Rails.logger.info("[job] paid event=#{event.event_id}")
    when "payment.failed"    then Rails.logger.info("[job] failed event=#{event.event_id}")
    else                          Rails.logger.warn("[job] unknown event_type=#{event.event_type} event=#{event.event_id}")
    end
  end
end