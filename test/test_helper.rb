ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require "simplecov"

SimpleCov.start "rails" do
  skip "/app/channels/"
  skip "/app/controllers/sessions/"
  skip "/app/controllers/passwords/"
  skip "/app/jobs/"
  skip "/app/mailers/"

  group "Policies", "app/policies/"
  group "Services", "app/services/"
  group "Queries", "app/queries/"
  group "Models", "app/models/"
  group "Controllers", "app/controllers/"
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
