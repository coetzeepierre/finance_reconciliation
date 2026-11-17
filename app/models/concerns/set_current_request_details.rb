module SetCurrentRequestDetails
  extend ActiveSupport::Concern

  included do
    before_action :set_current_tenant
  end

  private

  def set_current_tenant
    if Current.user
      # Picks their first authorized tenant membership, or falls back if unassigned
      Current.tenant = Current.user.tenants.first || Tenant.first
    else
      Current.tenant = Tenant.first
    end
  end
end
