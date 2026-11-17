class Account < ApplicationRecord
  belongs_to :tenant
  has_many :raw_statement_lines, dependent: :destroy
  has_many :reconciled_movements, dependent: :destroy

  validates :account_number, presence: true, uniqueness: { scope: :tenant_id }
end
