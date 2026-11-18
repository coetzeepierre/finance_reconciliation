module Treasury
  class AccountsController < ApplicationController
    before_action :set_account, only: [:show]

    def index
      @accounts = Current.tenant.accounts.order(:account_number)
    end

    def show
      # Default to the current month-to-date or a sensible rolling window if params aren't passed
      @from_date = parse_date(params[:from_date], default: Date.current.beginning_of_month)
      @to_date   = parse_date(params[:to_date],   default: Date.current)

      begin
        @balance_summaries = ReconciledBalanceQuery.new(
          tenant: Current.tenant,
          account: @account,
          from_date: @from_date,
          to_date: @to_date
        ).call
      rescue ArgumentError => e
        flash.now[:alert] = "Invalid date range: #{e.message}"
        @from_date = Date.current.beginning_of_month
        @to_date   = Date.current
        @balance_summaries = ReconciledBalanceQuery.new(
          tenant: Current.tenant,
          account: @account,
          from_date: @from_date,
          to_date: @to_date
        ).call
      end

      @movements = @account.reconciled_movements
                           .where(value_date: @from_date..@to_date)
                           .order(posting_ts: :desc)
                           .limit(50)
    end

    private

    def set_account
      @account = Current.tenant.accounts.find(params[:id])
    end

    def parse_date(date_str, default:)
      return default if date_str.blank?

      Date.parse(date_str.to_s)
    rescue ArgumentError
      default
    end
  end
end
