class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :customer, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string  :status, null: false, default: "pending"   # pending | paid | failed
      t.timestamps
    end
  end
end