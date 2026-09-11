class PaymentEvent < ApplicationRecord
  has_paper_trail

  enum :status, { received: "received", processed: "processed", failed: "failed" }, default: :received

  validates :event_id, presence: true, uniqueness: true
  validates :event_type, presence: true
end
