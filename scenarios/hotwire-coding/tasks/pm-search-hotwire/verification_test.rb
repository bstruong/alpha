# frozen_string_literal: true

require "test_helper"
require "support/product_browser"

class PmSearchHotwireVerification < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include ProductBrowser
  include Rails.application.routes.url_helpers

  setup { Capybara.current_driver = :alpha_cuprite }
  teardown { Capybara.reset_sessions!; Capybara.use_default_driver }

  test "product live search filters notes in the frame" do
    Note.create!(title: "Alpha")
    Note.create!(title: "Beta")
    visit notes_path
    assert_selector "turbo-frame#notes"
    find("#query").set("Alp")
    assert_selector "#notes-list li", text: "Alpha", visible: true, wait: 5
    assert_no_selector "#notes-list li", text: "Beta", visible: true, wait: 5
  end
end
