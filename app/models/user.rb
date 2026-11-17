class User < ApplicationRecord
  has_secure_password

  belongs_to :tenant
  has_many :sessions, dependent: :destroy
  has_many :user_tenant_memberships, dependent: :destroy
  has_many :tenants, through: :user_tenant_memberships

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
