# frozen_string_literal: true

require "test_helper"
require "support/product_browser"

class RecipeFormLabelsVerification < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include ProductBrowser
  include Rails.application.routes.url_helpers

  setup { Capybara.current_driver = :alpha_cuprite }
  teardown { Capybara.reset_sessions!; Capybara.use_default_driver }

  test "product search input is labeled and required" do
    visit notes_path
    label = find("label[for=query]")
    assert_equal "Search", label.text
    input = find("#query")
    assert input[:required]
    assert_equal "query", input[:id]
  end
end
