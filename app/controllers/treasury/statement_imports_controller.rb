module Treasury
  class StatementImportsController < ApplicationController
    before_action :set_account

    def new
    end

    def create
      begin
        Ingestion::ParseStatementFileService.call(
          file_path: params[:file],
          target_tenant: Current.tenant,
          target_account: @account
        )
        redirect_to treasury_account_path(@account), notice: "Statement successfully imported and reconciled."
      rescue ArgumentError => e
        flash.now[:alert] = "Failed to parse statement: #{e.message}"
        render :new, status: :unprocessable_entity
      end
    end

    private

    def set_account
      @account = Current.tenant.accounts.find(params[:account_id])
    end
  end
end
