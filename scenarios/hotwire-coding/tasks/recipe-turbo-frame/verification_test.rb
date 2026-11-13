# frozen_string_literal: true

require "test_helper"
require "support/product_browser"

class RecipeTurboFrameVerification < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include ProductBrowser
  include Rails.application.routes.url_helpers

  setup { Capybara.current_driver = :alpha_cuprite }
  teardown { Capybara.reset_sessions!; Capybara.use_default_driver }

  test "product page exposes turbo-frame#notes in the DOM" do
    visit notes_path
    assert_selector "turbo-frame#notes"
    assert_selector "turbo-frame#notes #notes-list"
  end
end
