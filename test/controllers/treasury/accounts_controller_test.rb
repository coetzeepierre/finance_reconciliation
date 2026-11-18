require "test_helper"

class Treasury::AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @account = accounts(:americas_treasury)
    sign_in_as(@user)
  end

  test "index renders the current tenant's accounts" do
    get treasury_accounts_path

    assert_response :success
    assert_includes response.body, @account.account_number
  end

  test "show renders the selected account" do
    get treasury_account_path(@account)

    assert_response :success
    assert_select "h1", "Account: #{@account.account_number}"
  end
end
