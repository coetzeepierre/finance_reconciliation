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

ActiveRecord::Schema[8.1].define(version: 2026_11_26_111200) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tenant_id", null: false
    t.string "account_number"
    t.string "business_unit"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "account_number"], name: "index_accounts_on_tenant_id_and_account_number", unique: true
    t.index ["tenant_id"], name: "index_accounts_on_tenant_id"
  end

  create_table "raw_statement_lines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tenant_id", null: false
    t.uuid "account_id", null: false
    t.string "source_id"
    t.string "currency", limit: 3, null: false
    t.bigint "amount_cents", null: false
    t.date "value_date", null: false
    t.datetime "posting_ts", null: false
    t.string "category"
    t.text "description"
    t.string "status", default: "pending", null: false
    t.uuid "duplicate_of_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_raw_statement_lines_on_account_id"
    t.index ["tenant_id", "account_id", "currency", "amount_cents", "posting_ts"], name: "idx_raw_lines_near_dup_lookup"
    t.index ["tenant_id", "source_id"], name: "idx_unique_raw_source_per_tenant", unique: true, where: "(source_id IS NOT NULL)"
    t.index ["tenant_id"], name: "index_raw_statement_lines_on_tenant_id"
    t.check_constraint "currency::text = ANY (ARRAY['USD'::character varying::text, 'EUR'::character varying::text, 'GBP'::character varying::text, 'JPY'::character varying::text, 'CHF'::character varying::text])", name: "chk_raw_currency"
  end

  create_table "reconciled_movements", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "tenant_id", null: false
    t.uuid "account_id", null: false
    t.uuid "raw_statement_line_id", null: false
    t.string "currency", limit: 3, null: false
    t.bigint "amount_cents", null: false
    t.date "value_date", null: false
    t.datetime "posting_ts", null: false
    t.string "category"
    t.text "description"
    t.uuid "reversal_of_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_reconciled_movements_on_account_id"
    t.index ["raw_statement_line_id"], name: "index_reconciled_movements_on_raw_statement_line_id", unique: true
    t.index ["reversal_of_id"], name: "index_reconciled_movements_on_reversal_of_id", unique: true, where: "(reversal_of_id IS NOT NULL)"
    t.index ["tenant_id", "account_id", "currency", "amount_cents", "posting_ts"], name: "idx_reconciled_movements_near_dup_window"
    t.index ["tenant_id", "account_id", "currency", "value_date"], name: "idx_reconciled_movements_balance_query"
    t.index ["tenant_id"], name: "index_reconciled_movements_on_tenant_id"
    t.check_constraint "currency::text = ANY (ARRAY['USD'::character varying::text, 'EUR'::character varying::text, 'GBP'::character varying::text, 'JPY'::character varying::text, 'CHF'::character varying::text])", name: "chk_rec_currency"
  end

  create_table "sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "tenants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "slug", null: false
    t.string "shard", default: "default", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_tenants_on_slug", unique: true
  end

  create_table "user_tenant_memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "tenant_id", null: false
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id"], name: "index_user_tenant_memberships_on_tenant_id"
    t.index ["user_id"], name: "index_user_tenant_memberships_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "tenant_id", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
  end

  add_foreign_key "accounts", "tenants"
  add_foreign_key "raw_statement_lines", "accounts"
  add_foreign_key "raw_statement_lines", "tenants"
  add_foreign_key "reconciled_movements", "accounts"
  add_foreign_key "reconciled_movements", "raw_statement_lines"
  add_foreign_key "reconciled_movements", "reconciled_movements", column: "reversal_of_id", name: "fk_reconciled_movements_reversal"
  add_foreign_key "reconciled_movements", "tenants"
  add_foreign_key "sessions", "users"
  add_foreign_key "user_tenant_memberships", "tenants"
  add_foreign_key "user_tenant_memberships", "users"
  add_foreign_key "users", "tenants"
end
