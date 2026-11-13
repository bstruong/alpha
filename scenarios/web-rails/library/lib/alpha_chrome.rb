# frozen_string_literal: true

module AlphaChrome
  module_function

  CANDIDATES = [
    ENV["ALPHA_CHROME_PATH"],
    ENV["BROWSER_PATH"],
    ENV["CHROME_PATH"],
    File.expand_path("~/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome"),
    File.expand_path("~/.cache/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-linux64/chrome-headless-shell"),
    "/usr/bin/google-chrome-stable",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser"
  ].freeze

  def path
    CANDIDATES.compact.find { |p| File.executable?(p) }
  end

  def require_path!
    p = path
    return p if p

    raise "Chrome binary not found (set ALPHA_CHROME_PATH). Product grading requires headless Chromium."
  end
end
