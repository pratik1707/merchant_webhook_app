class Order < ApplicationRecord
  belongs_to :customer
  has_many :transactions

  enum :status, { pending: "pending", paid: "paid", failed: "failed" }

  validates :amount_cents, numericality: { greater_than: 0 }
end