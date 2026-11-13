# frozen_string_literal: true

require "test_helper"
require "support/product_browser"

class RecipeCentsRoundVerification < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include ProductBrowser
  include Rails.application.routes.url_helpers

  setup { Capybara.current_driver = :alpha_cuprite }
  teardown { Capybara.reset_sessions!; Capybara.use_default_driver }

  test "product receipt shows half-up cents" do
    visit notes_path(amount: "1.045")
    assert_selector "#receipt-cents", text: "105"
  end

  test "source avoids to_f" do
    src = File.read(Rails.root.join("lib/money_cents.rb"))
    refute_match(/\bto_f\b/, src)
  end
end
