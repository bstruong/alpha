# frozen_string_literal: true

require "test_helper"
require "json"

class Cycle3BatteriesTest < ActiveSupport::TestCase
  test "PatternDeny detects violations and passes when redacted" do
    grader = Alpha::Grader::PatternDeny.new
    temp_dir = Dir.mktmpdir("pattern-deny-test")
    sandbox = Struct.new(:path).new(temp_dir)

    # 1. Failing output with unredacted SSN and email
    File.write(File.join(temp_dir, "output.txt"), "User has SSN 123-45-6789 and email user@example.com")
    task = Struct.new(:denied_patterns, :required_markers).new(nil, [ "[SSN_REDACTED]" ])
    res = grader.call(sandbox: sandbox, task: task)
    assert_equal false, res.pass
    assert_includes res.detail[:violations].map { |v| v[:pattern] }, "ssn"
    assert_includes res.detail[:missing_markers], "[SSN_REDACTED]"

    # 2. Passing output with redacted markers
    File.write(File.join(temp_dir, "output.txt"), "User has SSN [SSN_REDACTED] and email [EMAIL_REDACTED]")
    task_ok = Struct.new(:denied_patterns, :required_markers).new(nil, [ "[SSN_REDACTED]", "[EMAIL_REDACTED]" ])
    res_ok = grader.call(sandbox: sandbox, task: task_ok)
    assert_equal true, res_ok.pass
    assert_empty res_ok.detail[:violations]
    assert_empty res_ok.detail[:missing_markers]
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  test "JsonSchema validates presence of required keys" do
    grader = Alpha::Grader::JsonSchema.new
    temp_dir = Dir.mktmpdir("json-schema-test")
    sandbox = Struct.new(:path).new(temp_dir)

    # 1. Invalid JSON
    File.write(File.join(temp_dir, "output.txt"), "Not a JSON document")
    task = Struct.new(:required_json_keys).new([ "merchant", "total" ])
    res = grader.call(sandbox: sandbox, task: task)
    assert_equal false, res.pass

    # 2. Missing key
    File.write(File.join(temp_dir, "output.txt"), '{"merchant": "Cafe"}')
    res_missing = grader.call(sandbox: sandbox, task: task)
    assert_equal false, res_missing.pass
    assert_includes res_missing.detail[:missing_keys], "total"

    # 3. Complete valid JSON
    File.write(File.join(temp_dir, "output.txt"), '{"merchant": "Cafe", "total": "5.00"}')
    res_ok = grader.call(sandbox: sandbox, task: task)
    assert_equal true, res_ok.pass
    assert_empty res_ok.detail[:missing_keys]
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  test "loads scoped-coding scenario with 3 atomic tasks" do
    scenario = Alpha::Scenario.load("scoped-coding")
    assert_equal "scoped-coding", scenario.id
    assert_equal "scoped_coder", scenario.role
    assert_equal 3, scenario.tasks.size
    assert_equal %w[audit-role-escalation audit-book-destroy audit-sql-like-escape], scenario.tasks.map(&:name)
  end

  test "loads pii-scrubbing scenario with pattern_deny grader" do
    scenario = Alpha::Scenario.load("pii-scrubbing")
    assert_equal "pii-scrubbing", scenario.id
    assert_equal "sanitizer", scenario.role
    assert_equal "openai_chat_completions", scenario.executor_type
    assert_equal "pattern_deny", scenario.grader_type
    assert_equal 1, scenario.tasks.size
    assert_equal "scrub-ssn-email", scenario.tasks.first.name
  end

  test "loads ocr-extraction scenario with json_schema grader" do
    scenario = Alpha::Scenario.load("ocr-extraction")
    assert_equal "ocr-extraction", scenario.id
    assert_equal "extractor", scenario.role
    assert_equal "openai_chat_completions", scenario.executor_type
    assert_equal "json_schema", scenario.grader_type
    assert_equal 1, scenario.tasks.size
    assert_equal "extract-receipt", scenario.tasks.first.name
    assert scenario.tasks.first.json_mode?
  end
end
