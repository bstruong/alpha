# frozen_string_literal: true

require "test_helper"

class SymptomJsonPipelineVerification < ActionDispatch::IntegrationTest
  test "product summary lists ok rows only" do
    payload = [
      { "id" => "b", "status" => "ok", "total" => "2" },
      { "id" => "a", "status" => "ok", "total" => "1" },
      { "id" => "c", "status" => "err", "total" => "9" }
    ].to_json

    post tools_summarize_path, params: { payload: payload }
    assert_response :success
    assert_select "#summary-rows li[data-id=a]", text: "a: 1"
    assert_select "#summary-rows li[data-id=b]", text: "b: 2"
    assert_select "#summary-rows li[data-id=c]", count: 0
  end
end
