# frozen_string_literal: true

require "test_helper"

class PmMiniParserVerification < ActionDispatch::IntegrationTest
  test "product config page shows last-write-wins pairs" do
    text = "# c\nFOO=1\n\nBAR = two\nFOO=3\n"
    post tools_parse_config_path, params: { text: text }
    assert_response :success
    assert_select "dd[data-key=FOO]", text: "3"
    assert_select "dd[data-key=BAR]", text: "two"
  end
end
