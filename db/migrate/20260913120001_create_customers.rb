class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :email, null: false
      t.timestamps
    end
    add_index :customers, :email, unique: true
  end
end