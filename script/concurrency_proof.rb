# bin/rails runner script/concurrency_proof.rb
#
# Proves that when a late webhook and reconciliation hit the SAME payment at the
# same moment, only one of them resolves it - and the order ships once.
THREADS = 10

ActiveRecord::Base.establish_connection(
  ActiveRecord::Base.connection_db_config.configuration_hash.merge(pool: THREADS + 2)
)

# Count fulfillments instead of running them.
FULFILLED = Queue.new
module CountFulfillments
  def perform_later(order_id)
    FULFILLED << order_id
    true
  end
end
FulfillOrderJob.singleton_class.prepend(CountFulfillments)

[PaymentEvent, Transaction, Order, Customer, ProviderCharge].each(&:delete_all)
customer = Customer.create!(email: "race@example.com")
order    = customer.orders.create!(amount_cents: 10_000)
txn      = order.transactions.create!(provider_reference_id: "ref_race", amount_cents: 10_000)

results  = Queue.new
start_at = Time.now + 1   # all threads fire together

threads = THREADS.times.map do |i|
  Thread.new do
    sleep [start_at - Time.now, 0].max
    ActiveRecord::Base.connection_pool.with_connection do
      t = Transaction.find(txn.id)
      results << ResolveTransaction.call(
        txn: t, outcome: "succeeded",
        source: i.even? ? :webhook : :reconciliation   # half webhooks, half reconciliation
      )
    end
  end
end
threads.each(&:join)

outcomes = []
outcomes << results.pop until results.empty?
fulfillments = []
fulfillments << FULFILLED.pop until FULFILLED.empty?

puts "\n=== #{THREADS} threads resolving the SAME payment simultaneously ==="
puts "resolved:         #{outcomes.count(:resolved)}"
puts "already_resolved: #{outcomes.count(:already_resolved)}"
puts "final status:     #{txn.reload.status} (resolved_by: #{txn.resolved_by})"
puts "order status:     #{order.reload.status}"
puts "fulfillments:     #{fulfillments.size}   <- must be 1, not #{THREADS}"
