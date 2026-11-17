class CreateReconciledMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciled_movements, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :raw_statement_line, type: :uuid, null: false, foreign_key: true, index: { unique: true }

      t.string :currency, limit: 3, null: false
      t.bigint :amount_cents, null: false
      t.date :value_date, null: false
      t.datetime :posting_ts, null: false
      t.string :category
      t.text :description

      # Linking reversals to original movements (each movement can only be reversed once)
      t.uuid :reversal_of_id
      t.timestamps

      t.index :reversal_of_id, unique: true, where: "reversal_of_id IS NOT NULL"
      t.index [:tenant_id, :account_id, :currency, :value_date],
              name: "idx_reconciled_movements_balance_query"
      t.index [:tenant_id, :account_id, :currency, :amount_cents, :posting_ts],
              name: "idx_reconciled_movements_near_dup_window"

    end
    # Database Constraints for Data Integrity
    execute <<~SQL
      ALTER TABLE raw_statement_lines
        ADD CONSTRAINT chk_raw_currency CHECK (currency IN ('USD', 'EUR', 'GBP', 'JPY', 'CHF'));
      ALTER TABLE reconciled_movements
        ADD CONSTRAINT chk_rec_currency CHECK (currency IN ('USD', 'EUR', 'GBP', 'JPY', 'CHF'));
      ALTER TABLE reconciled_movements
        ADD CONSTRAINT fk_reconciled_movements_reversal FOREIGN KEY (reversal_of_id) REFERENCES reconciled_movements(id);
    SQL
  end
end
