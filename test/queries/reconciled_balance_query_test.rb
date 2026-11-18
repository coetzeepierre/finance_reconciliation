require "test_helper"

class ReconciledBalanceQueryTest < ActiveSupport::TestCase
  setup do
    @tenant = tenants(:acme)
    @account = accounts(:americas_treasury)
    @from_date = Date.new(2026, 1, 10)
    @to_date = Date.new(2026, 1, 20)
  end

  test "returns balances and in-period raw-line status counts sorted by currency" do
    create_movement(currency: "USD", amount_cents: 1_000, value_date: @from_date - 1)
    create_movement(currency: "USD", amount_cents: 200, value_date: @from_date)
    create_movement(currency: "USD", amount_cents: -50, value_date: @to_date)
    create_movement(currency: "USD", amount_cents: 500, value_date: @to_date + 1)

    create_movement(currency: "EUR", amount_cents: 300, value_date: @from_date - 1)
    create_movement(currency: "EUR", amount_cents: 75, value_date: @to_date)

    create_raw_line(currency: "USD", amount_cents: 25, value_date: @from_date + 2, status: "duplicate")
    create_raw_line(currency: "USD", amount_cents: -25, value_date: @from_date + 3, status: "reversal")
    create_raw_line(currency: "USD", amount_cents: 10, value_date: @to_date + 1, status: "duplicate")

    results = query.call

    assert_equal %w[EUR USD], results.map { |result| result[:currency] }

    eur = results.first
    assert_equal Money.new(300, "EUR"), eur[:opening_balance]
    assert_equal Money.new(75, "EUR"), eur[:period_net_movement]
    assert_equal Money.new(375, "EUR"), eur[:closing_balance]
    assert_equal 1, eur[:reconciled_count]
    assert_equal 0, eur[:excluded_duplicates_count]
    assert_equal 0, eur[:reversals_count]

    usd = results.last
    assert_equal Money.new(1_000, "USD"), usd[:opening_balance]
    assert_equal Money.new(150, "USD"), usd[:period_net_movement]
    assert_equal Money.new(1_150, "USD"), usd[:closing_balance]
    assert_equal 2, usd[:reconciled_count]
    assert_equal 1, usd[:excluded_duplicates_count]
    assert_equal 1, usd[:reversals_count]
  end

  test "scopes movements to the requested tenant and account" do
    create_movement(currency: "USD", amount_cents: 100, value_date: @from_date)

    other_account = @tenant.accounts.create!(account_number: "OTHER-QUERY-ACCOUNT")
    create_movement(currency: "USD", amount_cents: 200, value_date: @from_date, account: other_account)

    other_tenant = Tenant.create!(name: "Other Query Tenant", slug: "other-query-#{SecureRandom.hex(6)}")
    other_account = other_tenant.accounts.create!(account_number: "OTHER-TENANT-ACCOUNT")
    create_movement(currency: "USD", amount_cents: 300, value_date: @from_date, tenant: other_tenant, account: other_account)

    results = query.call

    assert_equal ["USD"], results.map { |result| result[:currency] }
    assert_equal Money.new(100, "USD"), results.first[:period_net_movement]
  end

  test "returns no currencies when there are raw lines but no reconciled movements" do
    create_raw_line(currency: "GBP", amount_cents: 100, value_date: @from_date, status: "pending")

    assert_empty query.call
  end

  test "raises when the from date is later than the to date" do
    invalid_query = ReconciledBalanceQuery.new(
      tenant: @tenant,
      account: @account,
      from_date: @to_date,
      to_date: @from_date
    )

    assert_raises(ArgumentError) { invalid_query.call }
  end

  private

  def query
    ReconciledBalanceQuery.new(tenant: @tenant, account: @account, from_date: @from_date, to_date: @to_date)
  end

  def create_movement(currency:, amount_cents:, value_date:, tenant: @tenant, account: @account)
    raw_line = create_raw_line(
      currency: currency,
      amount_cents: amount_cents,
      value_date: value_date,
      status: "reconciled",
      tenant: tenant,
      account: account
    )

    ReconciledMovement.create!(
      tenant: tenant,
      account: account,
      raw_statement_line: raw_line,
      currency: currency,
      amount_cents: amount_cents,
      value_date: value_date,
      posting_ts: raw_line.posting_ts
    )
  end

  def create_raw_line(currency:, amount_cents:, value_date:, status:, tenant: @tenant, account: @account)
    RawStatementLine.create!(
      tenant: tenant,
      account: account,
      source_id: SecureRandom.uuid,
      currency: currency,
      amount_cents: amount_cents,
      value_date: value_date,
      posting_ts: Time.current,
      status: status
    )
  end
end
