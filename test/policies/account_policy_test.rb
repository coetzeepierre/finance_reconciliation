require "test_helper"

class AccountPolicyTest < ActiveSupport::TestCase
  setup do
    Current.reset
    @account = accounts(:americas_treasury)
  end

  teardown do
    Current.reset
  end

  test "allows viewing an account in the active tenant" do
    Current.tenant = @account.tenant
    policy = AccountPolicy.new(nil, @account)

    assert policy.show?
    assert policy.reconciled_balance?
  end

  test "denies viewing an account outside the active tenant" do
    Current.tenant = @account.tenant
    other_tenant = Tenant.create!(name: "Other Treasury", slug: "other-treasury", shard: "default")
    other_account = Account.create!(
      tenant: other_tenant,
      account_number: "other-treasury-ACC-01",
      business_unit: "Other Treasury"
    )
    policy = AccountPolicy.new(nil, other_account)

    assert_not policy.show?
    assert_not policy.reconciled_balance?
  end

  test "denies viewing an account without an active tenant" do
    Current.tenant = nil
    policy = AccountPolicy.new(nil, @account)

    assert_not policy.show?
    assert_not policy.reconciled_balance?
  end
end