# frozen_string_literal: true

require "test_helper"
require "support/product_browser"

class FixStimulusControllerVerification < ActiveSupport::TestCase
  include Capybara::DSL
  include Capybara::Minitest::Assertions
  include ProductBrowser
  include Rails.application.routes.url_helpers

  setup { Capybara.current_driver = :alpha_cuprite }
  teardown { Capybara.reset_sessions!; Capybara.use_default_driver }

  test "product search input triggers form requestSubmit" do
    Note.create!(title: "Alpha")
    Note.create!(title: "Beta")
    visit notes_path
    page.execute_script(<<~JS)
      window.__submitCount = 0;
      const form = document.querySelector("[data-search-target=form]");
      const orig = HTMLFormElement.prototype.requestSubmit;
      HTMLFormElement.prototype.requestSubmit = function(...args) {
        window.__submitCount += 1;
        return orig.apply(this, args);
      };
    JS
    find("#query").set("Alp")
    # input event should call filter -> requestSubmit
    assert_operator page.evaluate_script("window.__submitCount"), :>=, 1
  end
end
