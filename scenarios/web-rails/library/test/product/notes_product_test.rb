# frozen_string_literal: true

require "test_helper"
require "support/product_browser"

class NotesProductTest < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include ProductBrowser
  include Rails.application.routes.url_helpers

  setup do
    Capybara.current_driver = :alpha_cuprite
  end

  teardown do
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end

  test "notes page renders and receipt cents are visible" do
    visit notes_path(amount: "1.045")
    assert_text "Notes"
    assert_selector "#receipt-cents", text: "105"
    assert flex_row?(".search-form"), "expected .search-form to be a horizontal flex row"
  end
end
