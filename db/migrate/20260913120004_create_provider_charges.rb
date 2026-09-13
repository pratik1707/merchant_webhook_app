# Represents the PROVIDER's ledger, not ours. In production this data lives at
# Stripe/Adyen; here it's local so reconciliation has a real source of truth to check.
class CreateProviderCharges < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_charges do |t|
      t.string  :reference_id, null: false
      t.integer :amount_cents, null: false
      t.string  :status, null: false                       # succeeded | failed
      t.timestamps
    end
    add_index :provider_charges, :reference_id, unique: true
  end
end