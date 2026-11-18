class ReconciledMovement < ApplicationRecord
  SUPPORTED_CURRENCIES = %w[USD EUR GBP JPY CHF].freeze

  belongs_to :tenant
  belongs_to :account
  belongs_to :raw_statement_line
  belongs_to :reversal_of, class_name: "ReconciledMovement", optional: true
  has_one :reversal_movement, class_name: "ReconciledMovement", foreign_key: :reversal_of_id, dependent: :restrict_with_exception

  monetize :amount_cents, with_model_currency: :currency

  validates :currency, presence: true, inclusion: { in: SUPPORTED_CURRENCIES }
  validates :amount_cents, :value_date, :posting_ts, presence: true
  validates :raw_statement_line_id, uniqueness: true
  validates :reversal_of_id, uniqueness: true, allow_nil: true
end
