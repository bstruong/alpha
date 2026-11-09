# frozen_string_literal: true

require "test_helper"
require "openssl"

class Phase1SemanticsTest < AlphaTest
  test "Alpha::Http enables TLS verification for https URIs" do
    uri = URI.parse("https://example.com/v1/models")
    seen = {}
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |v| seen[:use_ssl] = v }
    fake.define_singleton_method(:verify_mode=) { |v| seen[:verify_mode] = v }
    fake.define_singleton_method(:request) { |_req| :ok }

    Net::HTTP.stub(:start, lambda { |*_args, **_kwargs, &blk| blk.call(fake) }) do
      result = Alpha::Http.start(uri, open_timeout: 1, read_timeout: 1) { |http| http.request(:get) }
      assert_equal :ok, result
    end

    assert_equal true, seen[:use_ssl]
    assert_equal OpenSSL::SSL::VERIFY_PEER, seen[:verify_mode]
  end

  test "Alpha::Http leaves http URIs without SSL" do
    uri = URI.parse("http://127.0.0.1:8080/v1/models")
    seen = {}
    fake = Object.new
    fake.define_singleton_method(:use_ssl=) { |v| seen[:use_ssl] = v }
    fake.define_singleton_method(:verify_mode=) { |v| seen[:verify_mode] = v }
    fake.define_singleton_method(:request) { |_req| :ok }

    Net::HTTP.stub(:start, lambda { |*_args, **_kwargs, &blk| blk.call(fake) }) do
      Alpha::Http.start(uri, open_timeout: 1, read_timeout: 1) { |http| http.request(:get) }
    end

    refute seen.key?(:use_ssl)
    refute seen.key?(:verify_mode)
  end

  test "unknown executor names raise instead of selecting Pi" do
    err = assert_raises(ArgumentError) { Alpha::Executor.resolve("typo_executor") }
    assert_match(/Unknown executor/, err.message)
    assert_instance_of Alpha::Executor::PiRpc, Alpha::Executor.resolve(nil)
    assert_instance_of Alpha::Executor::PiRpc, Alpha::Executor.resolve("pi")
  end

  test "configuration defaults qualification schema to v2" do
    Alpha.reset_config!
    assert_equal "alpha.qualification.v2", Alpha.config.qualification_schema
  end

  test "campaign status separates health gate verdict sufficiency qualification and routing" do
    records = [
      {
        task_name: "gate-hello", kind: "gate", pass: true, pass_at_1: true, scored: true, invalid: false,
        credit: 1.0, failure_class: "none", rung: "L0", tool_calls: 0, wall_ms: 1, graders: []
      }
    ]
    target = Alpha::InferenceTarget.new(
      base_url: "https://inference.example/v1",
      model_id: "demo",
      engine_preset: "demo"
    )
    res = Alpha::Report.build(
      "status-sep-#{Time.now.to_i}",
      scenario: Alpha::Scenario.load("qwen36-daily", only_task: "gate-hello"),
      model_id: "demo",
      prompt_preset: "shipping",
      inference_target: target,
      task_records: records,
      suite_complete: false
    )
    status = res[:payload]["status"]
    %w[execution_health gate_status benchmark_verdict statistical_sufficiency qualification_eligible routing_authority].each do |key|
      assert status.key?(key), "missing status.#{key}"
    end
    assert_equal "none", status["routing_authority"]
    assert_equal false, status["qualification_eligible"]
    assert_equal "incomplete", status["benchmark_verdict"]

    FileUtils.rm_rf(File.dirname(res[:summary_path]))
    FileUtils.rm_f(res[:report_path])
  end

  test "v2 report schema remains readable for archived fields" do
    # Preserve readers for historical v2 keys even when new runs omit repair fields.
    payload = {
      "schema" => "alpha.report.v2",
      "aggregate" => {
        "pass_at_1" => 0.5,
        "tasks_passed" => 1,
        "tasks_total" => 2,
        "repaired_count" => 1,
        "pass_final" => 1.0
      },
      "tasks" => [
        { "name" => "x", "pass_at_1" => false, "pass" => true, "repaired" => true, "kind" => "graded" }
      ]
    }
    md = Alpha::Report.render_markdown(payload.merge(
      "run_id" => "archived-v2",
      "scenario" => "qwen36-daily",
      "model_id" => "old",
      "prompt_preset" => "shipping"
    ))
    assert_includes md, "First-attempt success"
    assert_includes md, "alpha.report.v2"
  end
end
