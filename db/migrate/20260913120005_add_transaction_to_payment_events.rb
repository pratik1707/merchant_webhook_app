class AddTransactionToPaymentEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :payment_events, :transaction, foreign_key: true, null: true
  end
end