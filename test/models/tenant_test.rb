require "test_helper"

class TenantTest < ActiveSupport::TestCase
  test "requires a name" do
    tenant = Tenant.new(slug: "example")

    assert_not tenant.valid?
    assert_includes tenant.errors[:name], "can't be blank"
  end

  test "requires a slug" do
    tenant = Tenant.new(name: "Example")

    assert_not tenant.valid?
    assert_includes tenant.errors[:slug], "can't be blank"
  end

  test "requires a unique slug" do
    tenant = Tenant.new(name: "Another tenant", slug: tenants(:acme).slug)

    assert_not tenant.valid?
    assert_includes tenant.errors[:slug], "has already been taken"
  end
end
