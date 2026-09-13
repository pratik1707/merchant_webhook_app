require "test_helper"

class ResolveTransactionTest < ActiveSupport::TestCase
  setup do
    purge_payment_data!
    @customer = Customer.create!(email: "resolve@example.com")
    @order    = @customer.orders.create!(amount_cents: 10_000)
    @txn      = @order.transactions.create!(provider_reference_id: "ref_resolve",
                                            amount_cents: 10_000)
  end

  test "resolves a pending payment, pays the order, fulfills exactly once" do
    assert_equal :resolved,
                 ResolveTransaction.call(txn: @txn, outcome: "succeeded", source: :webhook)

    assert_equal "succeeded", @txn.reload.status
    assert_equal "webhook",   @txn.resolved_by
    assert_not_nil            @txn.resolved_at
    assert_equal "paid",      @order.reload.status
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end

  test "a failed outcome fails the order and does not fulfill" do
    assert_equal :resolved,
                 ResolveTransaction.call(txn: @txn, outcome: "failed", source: :webhook)

    assert_equal "failed", @txn.reload.status
    assert_equal "failed", @order.reload.status
    assert_enqueued_jobs 0, only: FulfillOrderJob
  end

  test "a second resolve is a no-op and does not fulfill twice" do
    ResolveTransaction.call(txn: @txn, outcome: "succeeded", source: :webhook)

    result = ResolveTransaction.call(txn: @txn.reload, outcome: "succeeded",
                                     source: :reconciliation)

    assert_equal :already_resolved, result
    assert_equal "webhook", @txn.reload.resolved_by, "first writer's attribution must survive"
    assert_enqueued_jobs 1, only: FulfillOrderJob
  end

  test "a disagreeing outcome never overwrites a settled payment" do
    ResolveTransaction.call(txn: @txn, outcome: "succeeded", source: :webhook)

    result = ResolveTransaction.call(txn: @txn.reload, outcome: "failed",
                                     source: :reconciliation)

    assert_equal :already_resolved, result
    assert_equal "succeeded", @txn.reload.status,
                 "fulfillment may already have run - a settled status must not silently flip"
    assert_equal "paid", @order.reload.status
  end

  test "rejects a non-terminal outcome" do
    assert_raises(ArgumentError) { ResolveTransaction.call(txn: @txn, outcome: "pending", source: :webhook) }
    assert_raises(ArgumentError) { ResolveTransaction.call(txn: @txn, outcome: "maybe",   source: :webhook) }
  end
end
