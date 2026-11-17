puts "Seeding development data..."

tenant = Tenant.find_or_create_by!(slug: "acme-treasury") do |t|
  t.name = "Acme Treasury"
end

account = tenant.accounts.find_or_create_by!(account_number: "acme-treasury-ACC-01") do |a|
  a.business_unit = "Americas Treasury"
end

user = User.find_or_create_by!(email_address: "treasury.admin@acme.com") do |u|
  u.password = "securepassword123"
  u.tenant = tenant
end

UserTenantMembership.find_or_create_by!(user: user, tenant: tenant)

puts "Tenant: #{tenant.name}, Account: #{account.account_number}, and User Membership created successfully."
