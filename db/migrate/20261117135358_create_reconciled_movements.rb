class CreateReconciledMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :reconciled_movements, id: :uuid do |t|
      t.references :tenant, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :raw_statement_line, null: false, foreign_key: true, type: :uuid
      t.string :currency, limit: 3
      t.bigint :amount_cents
      t.date :value_date
      t.datetime :posting_ts
      t.string :category
      t.text :description
      t.uuid :reversal_of_id

      t.timestamps
    end
  end
end
