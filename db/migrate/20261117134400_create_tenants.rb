class CreateTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :tenants, id: :uuid do |t|
      t.string :name
      t.string :slug, null: false, index: { unique: true }
      t.string :shard, null: false, default: "default"

      t.timestamps
    end
  end
end
