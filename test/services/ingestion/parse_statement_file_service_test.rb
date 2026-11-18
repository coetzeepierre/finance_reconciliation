require "test_helper"

module Ingestion
  class ParseStatementFileServiceTest < ActiveSupport::TestCase
    setup do
      @tenant = tenants(:acme)
      @account = accounts(:americas_treasury)
      # Point to -the test Excel fixture
      @file_path = Rails.root.join("test", "fixtures", "files", "example_statements.xlsx")
    end

    test "parses the spreadsheet, and imports on the scoped tenant and account" do
      assert_difference "RawStatementLine.count", 217 do
        assert_difference "ReconciledMovement.count", 211 do
          assert_difference "RawStatementLine.duplicate.count", 5 do
            Ingestion::ParseStatementFileService.call(file_path: @file_path, target_tenant: @tenant, target_account: @account)
          end
        end
      end

      line = RawStatementLine.order(:created_at).last
      assert_equal "GBP", line&.currency
      assert_equal -84020742, line&.amount_cents
    end

    test "parses the spreadsheet, and imports on the scoped tenant with no account" do
      assert_difference "RawStatementLine.count", 1272 do
        assert_difference "ReconciledMovement.count", 1231 do
          assert_difference "RawStatementLine.duplicate.count", 27 do
            Ingestion::ParseStatementFileService.call(file_path: @file_path, target_tenant: @tenant)
          end
        end
      end

      line = RawStatementLine.order(:created_at).last
      assert_equal "EUR", line&.currency
      assert_equal -78536, line&.amount_cents
    end

    test "parses a CSV file and imports for the scoped tenant and account" do
      csv_path = Rails.root.join("test", "fixtures", "files", "example_statements.csv")

      assert_difference "RawStatementLine.count", 217 do
        assert_difference "ReconciledMovement.count", 211 do
          assert_difference "RawStatementLine.duplicate.count", 5 do
            Ingestion::ParseStatementFileService.call(
              file_path: csv_path,
              target_tenant: @tenant,
              target_account: @account
            )
          end
        end
      end
    end

    test "parses a CSV file and imports for the scoped tenant with no account" do
      csv_path = Rails.root.join("test", "fixtures", "files", "example_statements.csv")

      assert_difference "RawStatementLine.count", 1272 do
        assert_difference "ReconciledMovement.count", 1231 do
          assert_difference "RawStatementLine.duplicate.count", 27 do
            Ingestion::ParseStatementFileService.call(
              file_path: csv_path,
              target_tenant: @tenant
            )
          end
        end
      end
    end
  end
end
