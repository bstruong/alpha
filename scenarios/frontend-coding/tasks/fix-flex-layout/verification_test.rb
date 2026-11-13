# frozen_string_literal: true

require "test_helper"
require "support/product_browser"

class FixFlexLayoutVerification < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include ProductBrowser
  include Rails.application.routes.url_helpers

  setup { Capybara.current_driver = :alpha_cuprite }
  teardown { Capybara.reset_sessions!; Capybara.use_default_driver }

  test "product search form is a horizontal flex row" do
    visit notes_path
    assert flex_row?(".search-form"), "expected .search-form computed layout to be flex row"
  end
end
