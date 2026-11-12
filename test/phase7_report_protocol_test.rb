# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

class Phase7ReportProtocolTest < AlphaTest
  def with_protocol_tmpdir
    Dir.mktmpdir("alpha-phase7") do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "schemas"))
      FileUtils.mkdir_p(File.join(tmpdir, "results"))
      FileUtils.mkdir_p(File.join(tmpdir, "reports"))
      File.write(
        File.join(tmpdir, "schemas", "statistical-protocol.v1.yml"),
        <<~YAML
          schema: alpha.statistical_protocol.v1
          protocol_id: alpha-lab.held_out.first_attempt
          protocol_version: "1.0.0"
          unattended_enabled: false
          uncertainty:
            method: wilson_score_interval
            confidence_level: 0.95
          sample_size:
            min_effective_trials_unattended: 24
          counts:
            separate_coverage_from_reliability: true
        YAML
      )
      Alpha.configure do |c|
        c.root = tmpdir
        c.results_dir = File.join(tmpdir, "results")
        c.reports_dir = File.join(tmpdir, "reports")
        c.scenarios_dir = File.expand_path("../scenarios", __dir__)
      end
      yield tmpdir
    ensure
      Alpha.reset_config!
    end
  end

  test "wilson interval bounds" do
    lo, hi = Alpha::StatisticalProtocol.wilson_interval(24, 24)
    assert_operator lo, :>, 0.8
    assert_in_delta 1.0, hi, 1e-9
    assert_nil Alpha::StatisticalProtocol.wilson_interval(0, 0)
  end

  test "report leads with outcome sections and keeps tech supporting" do
    with_protocol_tmpdir do
      records = [
        {
          run_id: "phase7-report",
          task_name: "gate-hello",
          kind: "gate",
          pass: true,
          pass_at_1: true,
          scored: true,
          invalid: false,
          credit: 1.0,
          failure_class: "none",
          rung: "L0",
          trial: 1,
          trial_id: "phase7-report/gate-hello/trial-1",
          seed: 1001,
          evidence_uri: "results/runs/phase7-report/gate-hello/trial-1/result.json",
          tool_calls: 0,
          wall_ms: 10,
          graders: []
        }
      ]
      target = Alpha::InferenceTarget.new(
        base_url: "http://127.0.0.1:8080/v1",
        model_id: "demo",
        engine_preset: "demo"
      )
      Alpha::RunManifest.create!("phase7-report", seed: 1001)
      res = Alpha::Report.build(
        "phase7-report",
        scenario: Alpha::Scenario.load("qwen36-daily", only_task: "gate-hello"),
        model_id: "demo",
        prompt_preset: "shipping",
        inference_target: target,
        task_records: records,
        suite_complete: true
      )
      payload = res[:payload]
      assert_equal "alpha.statistical_protocol.v1", payload.dig("statistical_protocol", "schema")
      assert_equal "alpha-lab.held_out.first_attempt", payload.dig("statistical_protocol", "protocol_id")
      assert_equal false, payload.dig("statistical_protocol", "unattended_enabled")
      assert payload.key?("coverage")
      assert payload.key?("reliability")
      assert_equal "inadequate_for_unattended", payload.dig("status", "statistical_sufficiency")
      assert_equal "none", payload.dig("status", "routing_authority")

      md = File.read(res[:report_path])
      [
        "## Can do",
        "## Cannot reliably do",
        "## Not evaluated",
        "## Delegation decision",
        "## Evidence limits",
        "## Supporting evidence"
      ].each { |header| assert_includes md, header }
      assert_includes md, "Unattended: none"
      refute_match(/with 100% confidence|is 100% certain/i, md)
      assert_includes md, "Lease:"
      assert_operator md.index("## Can do"), :<, md.index("## Supporting evidence")
      assert_operator md.index("## Evidence limits"), :<, md.index("## Supporting evidence")
      assert_operator md.index("## Evidence limits"), :<, md.index("Lease:")
    end
  end
end
