class Tenant < ApplicationRecord
  has_many :user_tenant_memberships, dependent: :destroy
  has_many :users, through: :user_tenant_memberships

  has_many :accounts, dependent: :destroy
  has_many :raw_statement_lines, dependent: :destroy
  has_many :reconciled_movements, dependent: :destroy

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
end
