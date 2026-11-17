class Current < ActiveSupport::CurrentAttributes
  attribute :tenant, :user, :session
  delegate :user, to: :session, allow_nil: true
end
