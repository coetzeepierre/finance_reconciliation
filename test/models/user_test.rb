require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes email address" do
    user = User.new(email_address: "  USER@EXAMPLE.COM  ")

    assert_equal "user@example.com", user.email_address
  end
end
