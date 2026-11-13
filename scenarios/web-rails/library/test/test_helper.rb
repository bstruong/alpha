ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # One worker. Cache keys and Current are process-global, and a parallel
    # run would make the library-cache and audit checks order-dependent.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
  end
end

# Product (headless Chrome) tests opt in via `require "support/product_browser"`.
