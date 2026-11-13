# frozen_string_literal: true

require "test_helper"

class JsonPipelineTest < ActiveSupport::TestCase
  test "keeps ok rows mapped and sorted" do
    payload = [
      { "id" => "b", "status" => "ok", "total" => "2" },
      { "id" => "a", "status" => "ok", "total" => "1" },
      { "id" => "c", "status" => "err", "total" => "9" }
    ].to_json

    assert_equal(
      [ { "id" => "a", "total" => 1 }, { "id" => "b", "total" => 2 } ],
      JsonPipeline.summarize(payload)
    )
  end
end
