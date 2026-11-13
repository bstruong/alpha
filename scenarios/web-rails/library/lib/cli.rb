# frozen_string_literal: true

require "optparse"

module Cli
  module_function

  def parse(argv)
    options = { verbose: false }
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: tool [options] NAME"
      opts.on("-v", "--verbose", "Verbose output") { options[:verbose] = true }
      opts.on("-h", "--help", "Show help") do
        puts opts
        return { exit: 0, message: opts.to_s }
      end
    end

    begin
      parser.parse!(argv.dup)
    rescue OptionParser::InvalidOption => e
      return { exit: 2, message: e.message }
    end

    name = argv.reject { |a| a.start_with?("-") }.last
    if name.nil? || name.empty?
      return { exit: 1, message: "NAME required" }
    end

    msg = options[:verbose] ? "hello #{name} (verbose)" : "hello #{name}"
    { exit: 0, message: msg }
  end
end
