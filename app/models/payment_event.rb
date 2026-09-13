class PaymentEvent < ApplicationRecord
  has_paper_trail

  enum :status, {
  received:   "received",
  processing: "processing",   # claimed by a worker
  processed:  "processed",
  ignored:    "ignored",      # event type we don't act on
  orphaned:   "orphaned",     # no matching transaction for the reference
  failed:     "failed"
}
  validates :event_id, presence: true, uniqueness: true
  validates :event_type, presence: true

  belongs_to :payment_transaction,
           class_name: "Transaction",
           foreign_key: :transaction_id,
           optional: true
end