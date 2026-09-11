# Merchant Webhook App

A small Rails service that receives payment webhooks from an external payment provider,
guarantees idempotent processing, and hands off the actual business logic to a background
job via Sidekiq.

## How it works

1. **`WebhooksController#payments`** receives the webhook POST, validates `event_id` and
   `event_type` are present, and inserts a `PaymentEvent` row. Only an explicit whitelist of
   payload fields (`PERMITTED_PAYLOAD_FIELDS`) is persisted - anything else in the request
   body is dropped rather than stored as-is.
2. **Idempotency** is enforced at the database level: `event_id` has a unique index on
   `payment_events`, so a duplicate webhook delivery (providers commonly retry on timeout)
   fails to insert a second row instead of silently double-processing.
3. On a duplicate, the controller catches `ActiveRecord::RecordInvalid` /
   `ActiveRecord::RecordNotUnique` and responds `200 OK` with `duplicate_ignored` - returning
   a non-2xx here would just cause the provider to retry again.
4. On success, **`ProcessPaymentEventJob`** is enqueued via Sidekiq to do the actual work
   (mark an order paid/failed, trigger fulfillment, etc.), keeping the webhook response fast.
5. The job's own idempotency guard is atomic: it wraps the check-and-update in
   `event.with_lock { ... }`, taking a row-level database lock so two workers can never both
   pass the "already processed?" check for the same event. It also has automatic retry with
   backoff for transient failures.

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

## Testing

```bash
bin/rails test                          # controller/job/model/integration suite
bin/rails runner script/concurrency_test.rb   # proves the unique index holds under 20 concurrent threads
```

## Known limitations / next steps

- The `failed` status on `PaymentEvent` is defined but never actually set - an unrecognized
  `event_type`, or a job that exhausts all retries, currently just logs and leaves the record
  at `received` indefinitely, with no path to `failed` and no alerting.
- No webhook signature verification yet. The endpoint currently trusts any request that hits
  it; a production version needs to verify the provider's signature (e.g. an HMAC header)
  before treating the payload as genuine.
- No index on `status` or `event_type` yet - fine at current volume, but worth adding if you
  ever need to query "events stuck in `received`" for monitoring.