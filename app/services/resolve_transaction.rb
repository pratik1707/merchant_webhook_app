# The ONLY place a payment is ever decided.
#
# Called by both ProcessPaymentEventJob (a webhook arrived) and
# ReconcileStaleTransactionsJob (no webhook arrived; we asked the provider).
#
# Returns :resolved if THIS caller performed the transition, :already_resolved if
# something else got there first.
class ResolveTransaction
  def self.call(txn:, outcome:, source:)
    unless Transaction::TERMINAL.include?(outcome)
      raise ArgumentError, "outcome must be succeeded or failed, got #{outcome.inspect}"
    end

    won = ActiveRecord::Base.transaction do
      # One conditional UPDATE: only matches while still pending, so two concurrent
      # callers can never both pass. update_all skips callbacks, so updated_at by hand.
      rows = Transaction.where(id: txn.id, status: "pending")
                        .update_all(status: outcome,
                                    resolved_at: Time.current,
                                    resolved_by: source.to_s,
                                    updated_at: Time.current)

      if rows == 1
        # Same DB transaction: a crash here must not leave txn=succeeded / order=pending.
        txn.order.update!(status: outcome == "succeeded" ? "paid" : "failed")
        true
      else
        false
      end
    end

    unless won
      Rails.logger.info("[resolve] txn=#{txn.id} already resolved (source=#{source}), no-op")
      return :already_resolved
    end

    # AFTER commit, deliberately: the queue lives outside the database, so enqueueing
    # inside the transaction would survive a rollback and run against a row that
    # never existed.
    FulfillOrderJob.perform_later(txn.order_id) if outcome == "succeeded"

    Rails.logger.info("[resolve] txn=#{txn.id} -> #{outcome} (source=#{source})")
    :resolved
  end
end
