# frozen_string_literal: true

require "json"

module JsonPipeline
  module_function

  # Keep hashes with status == "ok", map to {id:, total:}, sort by id.
  def summarize(payload)
    rows = JSON.parse(payload)
    rows
      .select { |row| row["status"] == "ok" }
      .map { |row| { "id" => row["id"], "total" => Integer(row["total"]) } }
      .sort_by { |row| row["id"] }
  end
end
