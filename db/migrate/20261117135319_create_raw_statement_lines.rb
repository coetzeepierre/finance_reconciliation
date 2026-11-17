class CreateRawStatementLines < ActiveRecord::Migration[8.1]
  def change
    create_table :raw_statement_lines, id: :uuid do |t|
      t.references :tenant, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :source_id
      t.string :currency, limit: 3
      t.bigint :amount_cents
      t.date :value_date
      t.datetime :posting_ts
      t.string :category
      t.text :description
      t.string :status
      t.uuid :duplicate_of_id

      t.timestamps
    end
  end
end
