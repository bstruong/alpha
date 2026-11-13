# frozen_string_literal: true

require "test_helper"
require "support/product_browser"

class SliceNoteTagsVerification < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include ProductBrowser
  include Rails.application.routes.url_helpers

  setup { Capybara.current_driver = :alpha_cuprite }
  teardown { Capybara.reset_sessions!; Capybara.use_default_driver }

  test "product create-with-tag streams into frame and tag filter works" do
    Note.create!(title: "Home chore", tag: "home")
    visit notes_path

    assert_selector "turbo-frame#notes"
    assert_selector "#tag-query"
    assert_selector "#note_tag"

    within "#new-note" do
      fill_in "Title", with: "Ship it"
      find("#note_tag").set("work")
      click_button "Add"
    end

    assert_selector "turbo-frame#notes li[data-tag=work]", text: /Ship it/, wait: 5
    assert_selector "turbo-frame#notes .note-tag", text: "work"

    find("#tag-query").set("work")
    assert_selector "#notes-list li", text: /Ship it/, visible: true, wait: 5
    assert_no_selector "#notes-list li", text: /Home chore/, visible: true, wait: 5

    find("#tag-query").set("home")
    assert_selector "#notes-list li", text: /Home chore/, visible: true, wait: 5
    assert_no_selector "#notes-list li", text: /Ship it/, visible: true, wait: 5
  end
end
