require "test_helper"

class Api::V1::ReconciledBalancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @account = accounts(:americas_treasury)
    @from_date = Date.new(2026, 1, 10)
    @to_date = Date.new(2026, 1, 20)
    sign_in_as(@user)
  end

  test "show returns reconciled balances for the requested period" do
    create_movement(currency: "USD", amount_cents: 1_250, value_date: @from_date)

    get api_v1_account_reconciled_balance_path(@account), params: { from: @from_date, to: @to_date }

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal @account.tenant.slug, body["tenant_slug"]
    assert_equal @account.id, body.dig("account", "id")
    assert_equal @account.account_number, body.dig("account", "account_number")
    assert_equal @account.business_unit, body.dig("account", "business_unit")
    assert_equal @from_date.iso8601, body.dig("period", "from")
    assert_equal @to_date.iso8601, body.dig("period", "to")
    assert_equal [
      {
        "currency" => "USD",
        "opening_balance_cents" => 0,
        "period_net_movement_cents" => 1_250,
        "closing_balance_cents" => 1_250,
        "reconciled_count" => 1,
        "excluded_duplicates_count" => 0,
        "reversals_count" => 0
      }
    ], body["balances_by_currency"].map { |balance| balance.slice(
      "currency",
      "opening_balance_cents",
      "period_net_movement_cents",
      "closing_balance_cents",
      "reconciled_count",
      "excluded_duplicates_count",
      "reversals_count"
    ) }
  end

  private

  def create_movement(currency:, amount_cents:, value_date:)
    raw_line = RawStatementLine.create!(
      tenant: @account.tenant,
      account: @account,
      source_id: SecureRandom.uuid,
      currency: currency,
      amount_cents: amount_cents,
      value_date: value_date,
      posting_ts: Time.current,
      status: "reconciled"
    )

    ReconciledMovement.create!(
      tenant: @account.tenant,
      account: @account,
      raw_statement_line: raw_line,
      currency: currency,
      amount_cents: amount_cents,
      value_date: value_date,
      posting_ts: raw_line.posting_ts
    )
  end
end
