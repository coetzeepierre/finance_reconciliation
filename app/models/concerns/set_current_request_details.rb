module SetCurrentRequestDetails
  extend ActiveSupport::Concern

  included do
    before_action :set_current_tenant
  end

  private

  def set_current_tenant
    if current_user
      # For v1, resolve the user's primary or active tenant membership
      Current.tenant = current_user.tenants.first || Tenant.first
    end
  end
end
