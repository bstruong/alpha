# frozen_string_literal: true

require "json"
require "fileutils"

# Writes a fixture pair to disk: source.txt (what the model reads) and
# expected.json (the certified answer key). One directory per fixture.
#
# Single Responsibility — only persists fixtures; knows nothing about
# generation or scoring.
class FixtureWriter
  def initialize(root:)
    @root = root
  end

  # name: a slug like "chase_checking_2024_01_clean"
  # Returns the directory it wrote to.
  def write(name:, source_text:, statement:)
    dir = File.join(@root, name)
    FileUtils.mkdir_p(dir)

    File.write(File.join(dir, "source.txt"), source_text)
    File.write(
      File.join(dir, "expected.json"),
      JSON.pretty_generate(statement.to_expected_json)
    )
    dir
  end
end
