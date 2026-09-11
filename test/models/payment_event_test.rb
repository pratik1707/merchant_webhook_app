require "test_helper"

class PaymentEventTest < ActiveSupport::TestCase
  test "requires event_id" do
    event = PaymentEvent.new(event_type: "payment.succeeded")
    assert_not event.valid?
  end

  test "requires event_type" do
    event = PaymentEvent.new(event_id: "evt_new_001")
    assert_not event.valid?
  end

  test "rejects duplicate event_id at the validation layer" do
    dup = PaymentEvent.new(event_id: payment_events(:succeeded_event).event_id, event_type: "payment.succeeded")
    assert_not dup.valid?
  end

  test "rejects duplicate event_id at the database layer even if validation is bypassed" do
    dup = PaymentEvent.new(event_id: payment_events(:succeeded_event).event_id, event_type: "payment.succeeded")
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save(validate: false) }
  end
end