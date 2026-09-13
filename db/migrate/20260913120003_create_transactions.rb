class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :order, null: false, foreign_key: true
      t.string   :provider_reference_id, null: false
      t.string   :status, null: false, default: "pending"  # pending | succeeded | failed
      t.integer  :amount_cents, null: false
      t.datetime :resolved_at
      t.string   :resolved_by                              # webhook | reconciliation
      t.timestamps
    end

    # the id we hand the provider, so its replies map back to exactly one row
    add_index :transactions, :provider_reference_id, unique: true

    # supports the reconciliation query: pending + older than N minutes
    add_index :transactions, [:status, :created_at]
  end
end