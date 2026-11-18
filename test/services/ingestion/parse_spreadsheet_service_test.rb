require "test_helper"

module Ingestion
  class ParseSpreadsheetServiceTest < ActiveSupport::TestCase
    setup do
      @tenant = tenants(:acme)
      @account = accounts(:americas_treasury)
      # Point to the test Excel fixture
      @file_path = Rails.root.join("test", "fixtures", "files", "example_statements.xlsx")
    end

    test "parses the spreadsheet, and imports on the scoped tenant and account" do
      assert_difference "RawStatementLine.count", 8 do
        assert_difference "ReconciledMovement.count", 7 do
          assert_difference "RawStatementLine.duplicate.count", 1 do
            Ingestion::ParseSpreadsheetService.call(file_path: @file_path, target_tenant: @tenant, target_account: @account)
          end
        end
      end

      line = RawStatementLine.order(:created_at).last
      assert_equal "JPY", line.currency
      assert_equal -573, line.amount_cents
    end

    test "parses the spreadsheet, and imports on the scoped tenant with no account" do
      assert_difference "RawStatementLine.count", 32 do
        assert_difference "ReconciledMovement.count", 29 do
          assert_difference "RawStatementLine.duplicate.count", 1 do
            Ingestion::ParseSpreadsheetService.call(file_path: @file_path, target_tenant: @tenant)
          end
        end
      end

      line = RawStatementLine.order(:created_at).last
      assert_equal "GBP", line.currency
      assert_equal 7529, line.amount_cents
    end
  end
end
