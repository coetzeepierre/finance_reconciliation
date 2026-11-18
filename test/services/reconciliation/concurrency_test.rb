require "test_helper"

module Reconciliation
  class ConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      ReconciledMovement.delete_all
      RawStatementLine.delete_all
      Account.delete_all
      Tenant.delete_all

      @tenant = Tenant.create!(name: "Acme Treasury", slug: "acme-treasury")
      @account = @tenant.accounts.create!(account_number: "ACC-01", business_unit: "Americas Treasury")
    end

    teardown do
      ReconciledMovement.delete_all
      RawStatementLine.delete_all
      Account.delete_all
      Tenant.delete_all
    end

    test "concurrent exact re-deliveries with same source_id create only one movement" do
      barrier = Concurrent::CyclicBarrier.new(2)
      ts = Time.zone.parse("2024-06-15 10:00:00 UTC")

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            barrier.wait
            raw_line, newly_inserted = RawStatementLine.ingest_safely!(
              tenant: @tenant,
              account: @account,
              source_id: "SRC-ACM-9999",
              currency: "USD",
              amount_cents: 125_000,
              value_date: Date.new(2024, 6, 15),
              posting_ts: ts,
              description: "WIRE PAYMENT"
            )
            Reconciliation::ProcessLineService.new(raw_line).call if newly_inserted
          end
        end
      end

      threads.each(&:join)

      assert_equal 1, RawStatementLine.where(tenant: @tenant, source_id: "SRC-ACM-9999").count
      assert_equal 1, ReconciledMovement.where(tenant: @tenant, account: @account).count
    end

    test "concurrent near-duplicates without source_id serialize via account lock and count once" do
      barrier = Concurrent::CyclicBarrier.new(2)
      base_ts = Time.zone.parse("2024-07-17 09:26:44 UTC")

      threads = 2.times.map do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            barrier.wait
            raw_line, newly_inserted = RawStatementLine.ingest_safely!(
              tenant: @tenant,
              account: @account,
              source_id: nil,
              currency: "CHF",
              amount_cents: 367_050_958,
              value_date: Date.new(2024, 7, 17),
              posting_ts: base_ts + (i * 15).minutes,
              description: i.zero? ? "WIRE9304 REF6892" : "SEPA6189 OVERLAP FEED"
            )
            Reconciliation::ProcessLineService.new(raw_line).call if newly_inserted
          end
        end
      end

      threads.each(&:join)

      assert_equal 2, RawStatementLine.where(tenant: @tenant).count
      assert_equal 1, RawStatementLine.where(tenant: @tenant).reconciled.count
      assert_equal 1, RawStatementLine.where(tenant: @tenant).duplicate.count
      assert_equal 1, ReconciledMovement.where(tenant: @tenant).count
      assert_equal 367_050_958, ReconciledMovement.where(tenant: @tenant).sum(:amount_cents)
    end
  end
end
