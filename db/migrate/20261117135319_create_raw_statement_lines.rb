class CreateRawStatementLines < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_statement_lines, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true

      t.string :source_id
      t.string :currency, limit: 3, null: false
      t.bigint :amount_cents, null: false
      t.date :value_date, null: false
      t.datetime :posting_ts, null: false
      t.string :category
      t.text :description

      # Ingestion status tracking: pending, reconciled, duplicate, reversal, unmatched_reversal
      t.string :status, null: false, default: "pending"
      t.uuid :duplicate_of_id
      t.timestamps

      # Structural Idempotency: Exact re-deliveries carrying the same source_id cannot be duplicated
      t.index [:tenant_id, :source_id],
              unique: true,
              where: "source_id IS NOT NULL",
              name: "idx_unique_raw_source_per_tenant"

      # Index for efficient Near-Duplicate lookup windows
      t.index [:tenant_id, :account_id, :currency, :amount_cents, :posting_ts],
              name: "idx_raw_lines_near_dup_lookup"

    end
  end
end
