# frozen_string_literal: true

require "test_helper"

class NotesHotwireTest < ActionDispatch::IntegrationTest
  test "index wraps list in turbo-frame notes" do
    get notes_path
    assert_response :success
    assert_select "turbo-frame#notes"
  end

  test "search form has label and required query" do
    get notes_path
    assert_select "form.search-form"
    assert_select "label[for=query]", text: "Search"
    assert_select "input#query[required]"
  end

  test "search controller wired" do
    get notes_path
    assert_select "[data-controller~='search']"
    assert_select "[data-action*='search#filter']"
  end

  test "create responds with turbo stream prepend" do
    post notes_path, params: { note: { title: "Hello" } }, as: :turbo_stream
    assert_response :success
    assert_includes @response.media_type, "turbo-stream"
    assert_match(/turbo-stream[^>]*action="prepend"[^>]*target="notes-list"/, @response.body)
  end

  test "search filters notes" do
    Note.create!(title: "Alpha")
    Note.create!(title: "Beta")
    get notes_path, params: { q: "Alp" }
    assert_select "li", text: "Alpha"
    assert_select "li", text: "Beta", count: 0
  end

  test "receipt panel shows half-up cents" do
    get notes_path, params: { amount: "1.045" }
    assert_select "#receipt-cents", text: "105"
  end
end
