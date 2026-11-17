class AddTenantToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users,:tenant, type: :uuid, null: false, foreign_key: true
  end
end
