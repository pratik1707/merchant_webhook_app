# The side effect. Exists so tests can prove it runs exactly once per order,
# no matter how many events or paths resolved the payment.
class FulfillOrderJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    Rails.logger.info("[fulfill] shipping order #{order_id}")
  end
end
