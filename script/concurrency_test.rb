# Proves PaymentEvent's uniqueness guarantee holds under REAL concurrent access --
# not just sequential test calls. Run with: bin/rails runner script/concurrency_test.rb

EVENT_ID     = "evt_concurrency_demo_#{Time.now.to_i}"
THREAD_COUNT = 20

puts "Firing #{THREAD_COUNT} threads, all racing to create PaymentEvent event_id=#{EVENT_ID} ..."

success_count = 0
failure_count = 0
mutex = Mutex.new

threads = THREAD_COUNT.times.map do |i|
  Thread.new do
    # Each thread needs its OWN DB connection checked out from the pool --
    # ActiveRecord connections are not safe to share across threads.
    ActiveRecord::Base.connection_pool.with_connection do
      begin
        PaymentEvent.create!(
          event_id: EVENT_ID,
          event_type: "payment.succeeded",
          payload: { thread: i }
        )
        mutex.synchronize { success_count += 1 }
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        mutex.synchronize { failure_count += 1 }
      end
    end
  end
end

threads.each(&:join)

actual_rows = PaymentEvent.where(event_id: EVENT_ID).count

puts "Successes: #{success_count}"
puts "Failures (correctly rejected duplicates): #{failure_count}"
puts "Actual rows in DB for this event_id: #{actual_rows}"

if success_count == 1 && actual_rows == 1
  puts "PASS: exactly one thread won the race, database has exactly one row."
else
  puts "FAIL: expected exactly 1 success and 1 row -- something is broken."
end