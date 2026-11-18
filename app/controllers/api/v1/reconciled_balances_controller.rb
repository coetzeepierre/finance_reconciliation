module Api
  module V1
    class ReconciledBalancesController < ApplicationController
      before_action :authenticate_user!

      rescue_from ArgumentError, with: :handle_bad_request
      rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

      def show
        @account = Current.tenant.accounts.find(params[:account_id])
        raise ActiveRecord::RecordNotFound unless AccountPolicy.new(Current.user, @account).show?

        from_date = params[:from].presence ? Date.parse(params[:from]) : 30.days.ago.to_date
        to_date   = params[:to].presence   ? Date.parse(params[:to])   : Date.current

        balances = ReconciledBalanceQuery.new(
          tenant: Current.tenant,
          account: @account,
          from_date: from_date,
          to_date: to_date
        ).call

        render json: {
          tenant_slug: Current.tenant.slug,
          account: {
            id: @account.id,
            account_number: @account.account_number,
            business_unit: @account.business_unit
          },
          period: {
            from: from_date.iso8601,
            to: to_date.iso8601
          },
          balances_by_currency: balances.map { |b|
            {
              currency: b[:currency],
              opening_balance_cents: b[:opening_balance].cents,
              opening_balance_formatted: b[:opening_balance].format,
              period_net_movement_cents: b[:period_net_movement].cents,
              period_net_movement_formatted: b[:period_net_movement].format,
              closing_balance_cents: b[:closing_balance].cents,
              closing_balance_formatted: b[:closing_balance].format,
              reconciled_count: b[:reconciled_count],
              excluded_duplicates_count: b[:excluded_duplicates_count],
              reversals_count: b[:reversals_count]
            }
          }
        }
      end

      private

      def record_not_found(exception)
        render json: { error: exception.message }, status: :not_found
      end

      def handle_bad_request(exception)
        render json: { error: exception.message }, status: :bad_request
      end
    end
  end
end
