require "test_helper"

class ReconciledMovementTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.create!(name: "Test Tenant", slug: "test-tenant")
    @account = @tenant.accounts.create!(account_number: "ACC-TEST-01")
    @source_line_number = 0
  end

  test "persists a movement with its money amount and associations" do
    movement = build_movement

    assert movement.save
    assert_equal Money.new(12_345, "USD"), movement.amount
    assert_equal @tenant, movement.tenant
    assert_equal @account, movement.account
    assert_instance_of RawStatementLine, movement.raw_statement_line
  end

  test "requires the movement attributes and a supported currency" do
    movement = build_movement(
      currency: nil,
      amount_cents: nil,
      value_date: nil,
      posting_ts: nil
    )

    assert_not movement.valid?
    assert_includes movement.errors.attribute_names, :currency
    assert_includes movement.errors.attribute_names, :amount_cents
    assert_includes movement.errors.attribute_names, :value_date
    assert_includes movement.errors.attribute_names, :posting_ts

    movement.currency = "CAD"
    assert_not movement.valid?
    assert_includes movement.errors.attribute_names, :currency
  end

  test "requires each movement to have a unique raw statement line" do
    raw_statement_line = create_raw_statement_line
    create_movement(raw_statement_line: raw_statement_line)

    duplicate = build_movement(raw_statement_line: raw_statement_line)

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :raw_statement_line_id
  end

  test "allows only one reversal and exposes it through the reversal association" do
    original = create_movement
    reversal = create_movement(reversal_of: original)

    assert_equal reversal, original.reload.reversal_movement

    duplicate_reversal = build_movement(reversal_of: original)

    assert_not duplicate_reversal.valid?
    assert_includes duplicate_reversal.errors.attribute_names, :reversal_of_id
  end

  private

  def build_movement(**attributes)
    ReconciledMovement.new({
      tenant: @tenant,
      account: @account,
      raw_statement_line: create_raw_statement_line,
      currency: "USD",
      amount_cents: 12_345,
      value_date: Date.current,
      posting_ts: Time.current
    }.merge(attributes))
  end

  def create_movement(**attributes)
    build_movement(**attributes).tap(&:save!)
  end

  def create_raw_statement_line
    @source_line_number += 1
    RawStatementLine.create!(
      tenant: @tenant,
      account: @account,
      source_id: "SRC-TEST-#{@source_line_number}",
      currency: "USD",
      amount_cents: 12_345,
      value_date: Date.current,
      posting_ts: Time.current
    )
  end
end
