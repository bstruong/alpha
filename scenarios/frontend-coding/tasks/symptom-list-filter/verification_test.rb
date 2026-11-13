# frozen_string_literal: true

require "test_helper"
require "support/product_browser"

class SymptomListFilterVerification < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include ProductBrowser
  include Rails.application.routes.url_helpers

  setup { Capybara.current_driver = :alpha_cuprite }
  teardown { Capybara.reset_sessions!; Capybara.use_default_driver }

  test "product catalog filter narrows visible items" do
    visit notes_path
    assert_selector "[data-controller~='catalog-filter']"
    fill_in "catalog-query", with: "ban"
    assert_selector "#item-list li", text: "Banana", visible: true, wait: 5
    assert_no_selector "#item-list li", text: "Apple", visible: true, wait: 5
    fill_in "catalog-query", with: ""
    assert_selector "#item-list li", text: "Apple", visible: true, wait: 5
  end
end
