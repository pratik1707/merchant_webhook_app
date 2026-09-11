# Merchant Webhook App

A small Rails service that receives payment webhooks from an external payment provider,
guarantees idempotent processing, and hands off the actual business logic to a background
job via Sidekiq.

## How it works

1. **`WebhooksController#payments`** receives the webhook POST, validates `event_id` and
   `event_type` are present, and inserts a `PaymentEvent` row.
2. **Idempotency** is enforced at the database level: `event_id` has a unique index on
   `payment_events`, so a duplicate webhook delivery (providers commonly retry on timeout)
   fails to insert a second row instead of silently double-processing.
3. On a duplicate, the controller catches `ActiveRecord::RecordInvalid` /
   `ActiveRecord::RecordNotUnique` and responds `200 OK` with `duplicate_ignored` - returning
   a non-2xx here would just cause the provider to retry again.
4. On success, **`ProcessPaymentEventJob`** is enqueued via Sidekiq to do the actual work
   (mark an order paid/failed, trigger fulfillment, etc.), keeping the webhook response fast.
5. The job has its own idempotency guard (`return if event.status == "processed"`) to cover
   duplicate job enqueues, plus automatic retry with backoff for transient failures.

## Requirements

- Ruby / Rails
- PostgreSQL (or another DB that supports unique indexes + `RecordNotUnique`)
- Redis (for Sidekiq)
- Sidekiq

## Setup

```bash
bundle install
rails db:create db:migrate
```

## Running

```bash
rails server
bundle exec sidekiq
```

## Known limitations / next steps

- The job's idempotency guard (`return if processed?`) is not atomic under true concurrency -
  see comments in `ProcessPaymentEventJob` for the `with_lock` / conditional-update fix if
  stricter guarantees are needed.
- `payload: params.to_unsafe_h` stores the raw webhook body; consider validating/whitelisting
  fields before persisting in production.