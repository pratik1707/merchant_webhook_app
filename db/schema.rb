# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_13_120005) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_customers_on_email", unique: true
  end

  create_table "orders", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_orders_on_customer_id"
  end

  create_table "payment_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload"
    t.datetime "processed_at"
    t.string "status", default: "received", null: false
    t.bigint "transaction_id"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_payment_events_on_event_id", unique: true
    t.index ["transaction_id"], name: "index_payment_events_on_transaction_id"
  end

  create_table "provider_charges", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "reference_id", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["reference_id"], name: "index_provider_charges_on_reference_id", unique: true
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.string "provider_reference_id", null: false
    t.datetime "resolved_at"
    t.string "resolved_by"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_transactions_on_order_id"
    t.index ["provider_reference_id"], name: "index_transactions_on_provider_reference_id", unique: true
    t.index ["status", "created_at"], name: "index_transactions_on_status_and_created_at"
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "orders", "customers"
  add_foreign_key "payment_events", "transactions"
  add_foreign_key "transactions", "orders"
end
