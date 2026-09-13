class Transaction < ApplicationRecord
  belongs_to :order
  has_many :payment_events

  # NOTE: enum gives you succeeded!/failed! bang methods - do not use them.
  # Every status change must go through ResolveTransaction, which is the only
  # code that guards against two writers resolving the same payment twice.
  enum :status, { pending: "pending", succeeded: "succeeded", failed: "failed" }

  TERMINAL = %w[succeeded failed].freeze

  validates :provider_reference_id, presence: true, uniqueness: true
  validates :amount_cents, numericality: { greater_than: 0 }

  scope :stale, ->(age) { pending.where(created_at: ..age.ago) }
end