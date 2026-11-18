# app/queries/reconciled_balance_query.rb
class ReconciledBalanceQuery
  def initialize(tenant:, account:, from_date:, to_date:)
    @tenant = tenant
    @account = account
    @from_date = from_date.to_date
    @to_date = to_date.to_date
  end

  def call
    raise ArgumentError, "from_date must be <= to_date" if @from_date > @to_date

    # Only query currencies that exist in reconciled ledger
    base_scope = ReconciledMovement.where(tenant_id: @tenant.id, account_id: @account.id)
    currencies = base_scope.distinct.pluck(:currency).sort

    currencies.map do |currency|
      currency_scope = base_scope.where(currency: currency)

      opening_cents    = currency_scope.where("value_date < ?", @from_date).sum(:amount_cents)
      period_net_cents = currency_scope.where(value_date: @from_date..@to_date).sum(:amount_cents)
      closing_cents    = opening_cents + period_net_cents

      raw_period_scope = RawStatementLine.where(
        tenant_id: @tenant.id,
        account_id: @account.id,
        currency: currency,
        value_date: @from_date..@to_date
      )

      {
        currency: currency,
        opening_balance: Money.new(opening_cents, currency),
        period_net_movement: Money.new(period_net_cents, currency),
        closing_balance: Money.new(closing_cents, currency),
        reconciled_count: raw_period_scope.reconciled.count,
        excluded_duplicates_count: raw_period_scope.duplicate.count,
        reversals_count: raw_period_scope.reversal.count
      }
    end
  end
end
