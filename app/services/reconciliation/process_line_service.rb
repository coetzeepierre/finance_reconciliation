# app/services/reconciliation/process_line_service.rb
module Reconciliation
  class ProcessLineService
    NEAR_DUPLICATE_WINDOW = 24.hours
    REVERSAL_PATTERN = /\bREVERSAL OF\s+([A-Z0-9-]+)\b/i

    def initialize(raw_line)
      @raw_line = raw_line
      @tenant = raw_line.tenant
      @account = raw_line.account
    end

    def call
      # pessimistic lock on account
      account.with_lock do
        raw_line.reload
        # STOP WHEN NOT PENDING
        return unless raw_line.pending?

        if reversal_line?
          process_reversal!
        elsif (existing = find_near_duplicate)
          raw_line.update!(status: :duplicate, duplicate_of: existing)
        else
          promote_to_reconciled!
        end
      end
    end

    private

    attr_reader :raw_line, :tenant, :account

    def reversal_line?
      raw_line.description.to_s.match?(REVERSAL_PATTERN)
    end

    def target_reversal_source_id
      raw_line.description.to_s.match(REVERSAL_PATTERN)&.captures&.first&.upcase
    end

    def process_reversal!
      target_id = target_reversal_source_id

      # Search first by raw statement line source_id, fallback to raw_statement_line id
      original_movement = ReconciledMovement
        .joins(:raw_statement_line)
        .find_by(
          tenant_id: tenant.id,
          account_id: account.id,
          currency: raw_line.currency,
          raw_statement_lines: { source_id: target_id }
        )

      if original_movement &&
         original_movement.amount_cents == -raw_line.amount_cents &&
         !ReconciledMovement.exists?(reversal_of_id: original_movement.id)
        raw_line.update!(status: :reversal)
        create_ledger_movement!(reversal_of_id: original_movement.id)
      else
        raw_line.update!(status: :unmatched_reversal)
      end
    end

    def find_near_duplicate
      return nil if raw_line.source_id.present?

      window = (raw_line.posting_ts - NEAR_DUPLICATE_WINDOW)..(raw_line.posting_ts + NEAR_DUPLICATE_WINDOW)

      ReconciledMovement
        .where(
          tenant_id: tenant.id,
          account_id: account.id,
          currency: raw_line.currency,
          amount_cents: raw_line.amount_cents,
          posting_ts: window
        )
        .order(:posting_ts)
        .first
    end

    def promote_to_reconciled!
      raw_line.update!(status: :reconciled)
      create_ledger_movement!
    end

    def create_ledger_movement!(reversal_of_id: nil)
      ReconciledMovement.create!(
        tenant: tenant,
        account: account,
        raw_statement_line: raw_line,
        currency: raw_line.currency,
        amount_cents: raw_line.amount_cents,
        value_date: raw_line.value_date,
        posting_ts: raw_line.posting_ts,
        category: raw_line.category,
        description: raw_line.description,
        reversal_of_id: reversal_of_id
      )
    end
  end
end
