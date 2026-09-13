# bin/rails runner script/reconciliation_demo.rb
#
# Runs jobs synchronously so the demo needs neither Redis nor a Sidekiq worker.
ActiveJob::Base.queue_adapter = :inline

DROP_RATE = ENV.fetch("DROP_RATE", "0.2").to_f
COUNT     = ENV.fetch("COUNT", "100").to_i

[PaymentEvent, Transaction, Order, Customer, ProviderCharge].each(&:delete_all)
customer = Customer.create!(email: "demo@example.com")

dropped = 0
COUNT.times do
  drop = rand < DROP_RATE
  dropped += 1 if drop
  InitiatePayment.call(customer: customer, amount_cents: 10_000, drop_webhook: drop)
end

puts "\n=== #{COUNT} payments, #{(DROP_RATE * 100).round}% webhook drop rate (#{dropped} dropped) ==="
puts "\n--- after webhooks ---"
puts "resolved:      #{Transaction.succeeded.count}"
puts "stuck pending: #{Transaction.pending.count}   <- charged, nothing shipped, nobody knows"

Transaction.pending.update_all(created_at: 1.hour.ago)   # simulate 15+ minutes passing

puts "\n--- running reconciliation ---"
puts ReconcileStaleTransactionsJob.new.perform.to_json

puts "\n--- final ---"
puts "orders paid:   #{Order.paid.count} / #{COUNT}"
puts "still pending: #{Transaction.pending.count}"
puts "resolved by:   #{Transaction.succeeded.group(:resolved_by).count}"
