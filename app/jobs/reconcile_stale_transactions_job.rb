# Finds payments stuck pending too long and asks the provider what actually happened.
# This is the only thing that can detect a webhook that never arrived: absence of a
# webhook produces no event, so nothing else in the system will ever notice.
class ReconcileStaleTransactionsJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 15.minutes
  BATCH_SIZE  = 200

  def perform
    stats = { checked: 0, resolved: 0, already_resolved: 0, still_pending: 0 }

    Transaction.stale(STALE_AFTER).find_each(batch_size: BATCH_SIZE) do |txn|
      stats[:checked] += 1

      outcome = SimulatedProvider.status_for(txn.provider_reference_id)

      if Transaction::TERMINAL.include?(outcome)
        stats[ResolveTransaction.call(txn: txn, outcome: outcome, source: :reconciliation)] += 1
      else
        # Provider has no outcome yet (e.g. an ACH debit still clearing). "pending"
        # means lost OR in flight - only the provider can tell you which.
        stats[:still_pending] += 1
      end
    end

    Rails.logger.info("[reconciliation] #{stats.to_json}")
    stats
  end
end
