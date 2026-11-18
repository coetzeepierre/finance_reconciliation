require "test_helper"

module Reconciliation
  class ProcessLineServiceTest < ActiveSupport::TestCase
    setup do
      @tenant = Tenant.create!(name: "Test Tenant", slug: "test-tenant")
      @account = @tenant.accounts.create!(account_number: "ACC-TEST-01")
    end

    test "reconciles a pending line and copies its movement fields" do
      line = create_line(source_id: "SRC-001", category: "fees", description: "BANK FEE")

      ProcessLineService.new(line).call

      line.reload
      movement = ReconciledMovement.find_by!(raw_statement_line: line)
      assert line.reconciled?
      assert_equal 1, ReconciledMovement.count
      assert_equal line.amount_cents, movement.amount_cents
      assert_equal line.currency, movement.currency
      assert_equal line.value_date, movement.value_date
      assert_equal line.posting_ts, movement.posting_ts
      assert_equal line.category, movement.category
      assert_equal line.description, movement.description
    end

    test "marks rows with no source-id matching line as a duplicate" do
      original = create_line(source_id: "SRC-ORIGINAL")
      ProcessLineService.new(original).call

      original_movement = ReconciledMovement.find_by!(raw_statement_line: original)
      duplicate = create_line(posting_ts: original.posting_ts + 1.hour)

      ProcessLineService.new(duplicate).call

      duplicate.reload
      assert duplicate.duplicate?
      assert_equal original_movement.id, duplicate.duplicate_of_id
      assert_equal 1, ReconciledMovement.count
    end

    test "links a valid reversal to its original movement" do
      original = create_line(source_id: "SRC-ORIGINAL")
      ProcessLineService.new(original).call
      original_movement = ReconciledMovement.find_by!(raw_statement_line: original)
      reversal = create_line(
        amount_cents: -original.amount_cents,
        description: "REVERSAL OF SRC-ORIGINAL"
      )

      ProcessLineService.new(reversal).call

      reversal.reload
      reversal_movement = ReconciledMovement.find_by!(raw_statement_line: reversal)
      assert reversal.reversal?
      assert_equal original_movement.id, reversal_movement.reversal_of_id
      assert_equal 2, ReconciledMovement.count
    end

    test "marks reversals with a missing target or mismatched amount as unmatched" do
      missing_target = create_line(description: "REVERSAL OF SRC-MISSING", amount_cents: -10_000)
      original = create_line(source_id: "SRC-ORIGINAL")
      ProcessLineService.new(original).call
      mismatched_amount = create_line(
        description: "REVERSAL OF SRC-ORIGINAL",
        amount_cents: -9_999
      )

      ProcessLineService.new(missing_target).call
      ProcessLineService.new(mismatched_amount).call

      assert missing_target.reload.unmatched_reversal?
      assert mismatched_amount.reload.unmatched_reversal?
      assert_equal 1, ReconciledMovement.count
    end

    test "does not process a line that is no longer pending" do
      line = create_line(status: :reconciled)

      ProcessLineService.new(line).call

      assert line.reload.reconciled?
      assert_equal 0, ReconciledMovement.count
    end

    private

    def create_line(attributes = {})
      RawStatementLine.create!(
        {
          tenant: @tenant,
          account: @account,
          source_id: nil,
          currency: "USD",
          amount_cents: 10_000,
          value_date: Date.new(2024, 6, 15),
          posting_ts: Time.zone.parse("2024-06-15 10:00:00 UTC"),
          category: "transfers",
          description: "WIRE PAYMENT",
          status: :pending
        }.merge(attributes)
      )
    end
  end
end
