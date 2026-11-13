# frozen_string_literal: true

module LineParser
  module_function

  # Parse "KEY=VALUE" lines; ignore blanks and # comments; last key wins.
  def parse(text)
    result = {}
    text.each_line do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")
      next unless line.include?("=")

      key, value = line.split("=", 2)
      result[key.strip] = value.strip
    end
    result
  end
end
