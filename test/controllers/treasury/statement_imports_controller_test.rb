require "test_helper"
require "minitest/autorun"
require "minitest/mock"

class Treasury::StatementImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @account = accounts(:americas_treasury)
    sign_in_as(@user)
  end

  test "new renders the statement upload form" do
    get new_treasury_account_statement_import_path(@account)

    assert_response :success
    assert_select "h1", "Upload Statement"
    assert_includes response.body, @account.account_number
    assert_select 'input[type="file"][name="file"]'
  end

  test "create requires a file upload" do
    post treasury_account_statement_import_path(@account)

    assert_response :unprocessable_entity
    assert_equal "Failed to parse statement: Missing file to process", response.request.flash[:alert]
  end

  test "raises ArgumentError on excluded file_path" do
    post treasury_account_statement_import_path(@account), params: {
      file: nil
    }
    assert_response :unprocessable_entity
    assert_equal "Failed to parse statement: Missing file to process", response.request.flash[:alert]
  end

  test "create imports an uploaded statement file" do
    assert_difference "RawStatementLine.count", 217 do
      assert_difference "ReconciledMovement.count", 211 do
        assert_difference "RawStatementLine.duplicate.count", 5 do
          post treasury_account_statement_import_path(@account), params: {
            file: fixture_file_upload("example_statements.csv", "text/csv")
          }
        end
      end
    end

    assert_redirected_to treasury_account_path(@account)
    assert_equal "Statement successfully imported and reconciled.", response.request.flash[:notice]
  end
end
