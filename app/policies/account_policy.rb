# app/policies/account_policy.rb
class AccountPolicy < ApplicationPolicy
  def show?
    # make sure the account belongs to this user's active tenant scope
    record.tenant_id == Current.tenant&.id
  end

  def reconciled_balance?
    show?
  end
end
