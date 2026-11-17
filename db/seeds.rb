# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

puts "Seeding development data..."
unless User.count.positive?
  User.create!({
                 email_address: "test@ripple.com",
                 password: "ripple123"
               })
end

tenant = Tenant.find_or_create_by!(slug: "acme-treasury") do |t|
  t.name = "Acme Treasury"
end

account = tenant.accounts.find_or_create_by!(account_number: "acme-treasury-ACC-01") do |a|
  a.business_unit = "Americas Treasury"
end

puts "Tenant: #{tenant.name} & Account: #{account.account_number} created successfully."
