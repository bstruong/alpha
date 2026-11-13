# frozen_string_literal: true

require "test_helper"
require "support/product_browser"

class SymptomTurboStreamVerification < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include ProductBrowser
  include Rails.application.routes.url_helpers

  setup { Capybara.current_driver = :alpha_cuprite }
  teardown { Capybara.reset_sessions!; Capybara.use_default_driver }

  test "product create prepends note into the list" do
    visit notes_path
    fill_in "Title", with: "Streamed Note"
    click_button "Add"
    assert_selector "#notes-list li", text: "Streamed Note", visible: true
  end
end
