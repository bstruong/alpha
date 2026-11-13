# frozen_string_literal: true

require "test_helper"
require "support/product_browser"

class PmA11yKeyboardVerification < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include ProductBrowser
  include Rails.application.routes.url_helpers

  setup { Capybara.current_driver = :alpha_cuprite }
  teardown { Capybara.reset_sessions!; Capybara.use_default_driver }

  test "product help dialog focuses close then continue" do
    visit notes_path
    find("#help-open").click
    assert_equal "help-close", page.evaluate_script("document.activeElement && document.activeElement.id")
    find("#help-close").click
    assert_equal "after-help", page.evaluate_script("document.activeElement && document.activeElement.id")
  end
end
