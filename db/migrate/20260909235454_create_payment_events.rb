class CreatePaymentEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_events do |t|
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :status, null: false, default: "received"
      t.jsonb :payload
      t.datetime :processed_at

      t.timestamps
    end
    add_index :payment_events, :event_id, unique: true
  end
end