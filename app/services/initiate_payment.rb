# The checkout side - the half the app did not have before. Without our own record
# of what we are waiting for, there is nothing for reconciliation to compare against.
class InitiatePayment
  def self.call(customer:, amount_cents:, drop_webhook: false, fail_charge: false)
    txn = ActiveRecord::Base.transaction do
      order = customer.orders.create!(amount_cents: amount_cents)
      order.transactions.create!(
        provider_reference_id: "ref_#{SecureRandom.hex(8)}",
        amount_cents: amount_cents
      )
    end

    # provider_reference_id doubles as the outbound idempotency key: a retry after a
    # timeout returns the original charge instead of creating a second one.
    SimulatedProvider.charge!(
      reference_id:    txn.provider_reference_id,
      amount_cents:    amount_cents,
      idempotency_key: txn.provider_reference_id,
      drop_webhook:    drop_webhook,
      fail_charge:     fail_charge
    )

    txn
  end
end
