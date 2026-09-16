
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