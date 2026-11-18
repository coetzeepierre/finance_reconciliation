module Treasury
  class StatementImportsController < ApplicationController
    before_action :set_account

    def new
      # Renders the upload form
    end

    def create
      if params[:file].present?
        service = Ingestion::ParseSpreadsheetService.new(
          target_tenant: Current.tenant,
          target_account: @account,
          file_path: params[:file]
        )

        if service.call
          redirect_to treasury_account_path(@account), notice: "Statement successfully parsed and reconciled."
        else
          flash.now[:alert] = "Failed to process the CSV file."
          render :new, status: :unprocessable_entity
        end
      else
        flash.now[:alert] = "Please select a CSV file to upload."
        render :new, status: :unprocessable_entity
      end
    end

    private

    def set_account
      @account = Current.tenant.accounts.find(params[:account_id])
    end
  end
end
