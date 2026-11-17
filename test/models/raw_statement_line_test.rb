require "test_helper"

class RawStatementLineTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.create!(name: "Test Tenant", slug: "test-tenant")
    @account = @tenant.accounts.create!(account_number: "ACC-TEST-01")
  end

  test "ingest_safely! negate duplicates when creating on same source_id" do
    attrs = {
      tenant: @tenant,
      account: @account,
      source_id: "SRC-TEST-001",
      currency: "USD",
      amount_cents: 10000,
      value_date: Date.current,
      posting_ts: Time.current
    }

    line1, created1 = RawStatementLine.ingest_safely!(attrs)
    line2, created2 = RawStatementLine.ingest_safely!(attrs)

    assert created1, "First ingestion should create record"
    assert_not created2, "Second ingestion with same source_id should be skipped"

    assert_equal line1.id, line2.id, "Should return the existing record"
    assert_equal 1, RawStatementLine.count
  end
end
