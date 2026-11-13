# frozen_string_literal: true

require "capybara/minitest"
require "capybara/cuprite"
require "alpha_chrome"

module ProductBrowser
  def self.configure!
    path = AlphaChrome.require_path!

    Capybara.register_driver(:alpha_cuprite) do |app|
      Capybara::Cuprite::Driver.new(
        app,
        browser_options: {
          "no-sandbox": nil,
          "disable-gpu": nil,
          "disable-dev-shm-usage": nil
        },
        browser_path: path,
        headless: true,
        timeout: 20,
        process_timeout: 25,
        window_size: [ 1280, 800 ]
      )
    end

    Capybara.default_driver = :alpha_cuprite
    Capybara.javascript_driver = :alpha_cuprite
    Capybara.app = Rails.application
    Capybara.default_max_wait_time = 5
    Capybara.server = :puma, { Silent: true }
  end

  # Computed CSS property for the first matching selector.
  def computed_style(selector, property)
    page.evaluate_script(
      "getComputedStyle(document.querySelector(#{selector.to_json}))[#{property.to_json}]"
    )
  end

  # True when flex children of selector sit on one horizontal row.
  def flex_row?(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector(#{selector.to_json});
        if (!el) return false;
        const style = getComputedStyle(el);
        if (style.display !== "flex") return false;
        const dir = style.flexDirection;
        return dir === "row" || dir === "row-reverse";
      })()
    JS
  end
end

ProductBrowser.configure!
