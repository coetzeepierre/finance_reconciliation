require "test_helper"

class Treasury::StatementImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @account = accounts(:americas_treasury)
    sign_in_as(@user)
  end

  test "new renders the statement upload form" do
    get new_treasury_account_statement_import_path(@account)

    assert_response :success
    assert_select "h1", "Upload Statement CSV"
    assert_includes response.body, @account.account_number
    assert_select 'input[type="file"][name="file"]'
  end

  test "create requires a file upload" do
    post treasury_account_statement_import_path(@account)

    assert_response :unprocessable_entity
    assert_equal "Please select a CSV file to upload.", response.request.flash[:alert]
  end
end
