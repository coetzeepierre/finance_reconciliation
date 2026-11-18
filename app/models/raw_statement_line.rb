class RawStatementLine < ApplicationRecord
  SUPPORTED_CURRENCIES = %w[USD EUR GBP JPY CHF].freeze

  belongs_to :tenant
  belongs_to :account
  belongs_to :duplicate_of, class_name: "ReconciledMovement", optional: true
  has_one :reconciled_movement, dependent: :restrict_with_exception

  monetize :amount_cents, with_model_currency: :currency

  enum :status, {
    pending: "pending",
    reconciled: "reconciled",
    duplicate: "duplicate",
    reversal: "reversal",
    unmatched_reversal: "unmatched_reversal"
  }

  validates :currency, presence: true, inclusion: { in: SUPPORTED_CURRENCIES }
  validates :amount_cents, :value_date, :posting_ts, presence: true

  def self.ingest_safely!(attrs)
    source_id = attrs[:source_id].presence
    tenant = attrs.fetch(:tenant)
    account = attrs.fetch(:account)

    if source_id
      now = Time.current
      insert_attrs = attrs.except(:tenant, :account).merge(
        tenant_id: tenant.id,
        account_id: account.id,
        source_id: source_id,
        status: "pending",
        created_at: now,
        updated_at: now
      )

      result = insert(
        insert_attrs,
        unique_by: :idx_unique_raw_source_per_tenant,
        returning: %w[id]
      )

      if result.rows.any?
        # winning POSTGRESQL thread safety ensures ONE insert tied to POSTGRESQL UPSERT
        [find(result.rows.first.first), true]
      else
        # losing thread - look up existing on FAIL DO NOTHING - only one ever inserted!
        [find_by!(tenant_id: tenant.id, source_id: source_id), false]
      end
    else
      [create!(attrs.merge(source_id: nil, status: "pending")), true]
    end
  end
end
