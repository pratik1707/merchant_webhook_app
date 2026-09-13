# The provider's side of the ledger - deliberately NOT associated with our models.
# Reconciliation is only meaningful if this is an independent record.
class ProviderCharge < ApplicationRecord
  validates :reference_id, presence: true, uniqueness: true
end