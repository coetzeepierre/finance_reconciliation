class ReconciledMovement < ApplicationRecord
  belongs_to :tenant
  belongs_to :account
  belongs_to :raw_statement_line
end
