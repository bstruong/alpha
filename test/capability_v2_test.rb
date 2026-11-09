# frozen_string_literal: true

require "test_helper"
require "json"

class CapabilityV2Test < AlphaTest
  test "Rung ordering and normalize" do
    assert_equal "L2", Alpha::Rung.normalize("l2")
    assert Alpha::Rung.<=("L1", "L2")
    assert_equal "L3", Alpha::Rung.max("L1", "L3", "L0")
  end

  test "TrialOutcome marks infra exits invalid" do
    out = Alpha::TrialOutcome.classify(
      exit_reason: "error: connection refused",
      timed_out: false,
      agent_patch_empty: true
    )
    assert out[:invalid]
    refute out[:scored]
  end

  test "TrialOutcome scores honest model failures" do
    out = Alpha::TrialOutcome.classify(
      exit_reason: "completed",
      timed_out: false,
      agent_patch_empty: false
    )
    assert out[:scored]
    refute out[:invalid]
  end

  test "FailureClass distinguishes noop and infra" do
    assert_equal "infra", Alpha::FailureClass.classify(pass: false, invalid: true)
    assert_equal "none", Alpha::FailureClass.classify(pass: true, invalid: false)
    assert_equal "noop", Alpha::FailureClass.classify(
      pass: false, invalid: false, agent_patch_empty: true, grader_detail: {}
    )
  end

  test "Money helpers enforce integer cents and recon" do
    parsed = { "opening_cents" => 100, "closing_cents" => 150, "entries" => [ { "amount_cents" => 50 } ] }
    meta = Alpha::Grader::Money.validate_parsed_money!(
      parsed,
      required_cent_keys: %w[opening_cents closing_cents],
      recon: { "opening" => "opening_cents", "closing" => "closing_cents", "entries" => "entries" }
    )
    assert Alpha::Grader::Money.required_pass?(meta[:checks])
    refute meta[:recon_break]
  end

  test "Qualifier excludes invalid trials from Pass@1 rates but rejects infra rows" do
    summary = {
      "scenario" => "ocr-extraction",
      "prompt_preset" => "shipping",
      "suite_complete" => true,
      "dry_run" => false,
      "tasks" => [
        { "name" => "extract-receipt-template", "kind" => "graded", "pass_at_1" => true, "scored" => true, "rung" => "L0", "skill" => "ocr_extract", "credit" => 1.0, "trial" => 1, "trial_id" => "a" },
        { "name" => "extract-receipt", "kind" => "graded", "pass_at_1" => true, "scored" => true, "rung" => "L1", "skill" => "ocr_extract", "credit" => 1.0, "trial" => 1, "trial_id" => "b" },
        { "name" => "broken", "kind" => "graded", "pass_at_1" => false, "invalid" => true, "failure_class" => "infra", "rung" => "L1", "trial" => 1, "trial_id" => "c" }
      ]
    }
    verdict = Alpha::Qualifier.evaluate(summary, scenario: Alpha::Scenario.load("ocr-extraction"))
    refute verdict.qualified
    assert_match(/infrastructure-invalid|incomplete expected task set/, verdict.reason)
    assert_equal 1.0, verdict.graded_pass_at_1
    assert_equal "L1", verdict.max_rung
  end

  test "Qualifier qualifies complete clean ocr shipping suite" do
    summary = {
      "scenario" => "ocr-extraction",
      "prompt_preset" => "shipping",
      "suite_complete" => true,
      "dry_run" => false,
      "qualification_eligible" => true,
      "tasks" => [
        { "name" => "extract-receipt-template", "kind" => "graded", "pass_at_1" => true, "scored" => true, "rung" => "L0", "skill" => "ocr_extract", "credit" => 1.0, "trial" => 1, "trial_id" => "a" },
        { "name" => "extract-receipt", "kind" => "graded", "pass_at_1" => true, "scored" => true, "rung" => "L1", "skill" => "ocr_extract", "credit" => 1.0, "trial" => 1, "trial_id" => "b" }
      ]
    }
    verdict = Alpha::Qualifier.evaluate(summary, scenario: Alpha::Scenario.load("ocr-extraction"))
    assert verdict.qualified, verdict.reason
    assert_equal 1.0, verdict.graded_pass_at_1
    assert_equal "none", verdict.routing_authority
  end

  test "Nop executor registers and returns nop exit" do
    executor = Alpha::Executor.resolve("nop")
    assert_kind_of Alpha::Executor::Nop, executor
    sandbox = Struct.new(:path).new(Dir.mktmpdir("nop"))
    task = Struct.new(:name).new("x")
    res = executor.call(task: task, sandbox: sandbox, inference_target: nil, profile: nil)
    assert_equal "nop", res.exit_reason
    assert_equal 0, res.tool_calls
  ensure
    FileUtils.rm_rf(sandbox.path) if sandbox
  end

  test "CapabilityMap renders rows from summary payloads" do
    Dir.mktmpdir("capmap") do |tmpdir|
      run_id = "cap-run"
      run_dir = File.join(tmpdir, "runs", run_id)
      FileUtils.mkdir_p(run_dir)
      summary = {
        "schema" => "alpha.report.v2",
        "run_id" => run_id,
        "scenario" => "ocr-extraction",
        "model_id" => "qwen25-coder-14b",
        "prompt_preset" => "shipping",
        "aggregate" => {
          "pass_at_1" => 1.0,
          "highest_rung_passed" => "L1",
          "ceiling_rung" => "L1",
          "credit_mean" => 1.0,
          "failure_class_histogram" => { "none" => 1 }
        },
        "tasks" => [
          { "name" => "extract-receipt", "kind" => "graded", "pass_at_1" => true, "rung" => "L1", "skill" => "ocr_extract", "credit" => 1.0, "failure_class" => "none" }
        ]
      }
      File.write(File.join(run_dir, "summary.json"), JSON.pretty_generate(summary))
      rows = Alpha::CapabilityMap.build([ run_id ], results_dir: tmpdir)
      assert_equal 1, rows.size
      md = Alpha::CapabilityMap.render_markdown(rows)
      assert_match(/qwen25-coder-14b/, md)
      assert_match(/extractor/, md)
    end
  end

  test "Qualifier infers vault roles" do
    assert_equal "vault_extractor", Alpha::Qualifier.infer_role("vault-extract")
    assert_equal "vault_sanitizer", Alpha::Qualifier.infer_role("vault-sanitize")
    assert_equal "recon_ops", Alpha::Qualifier.infer_role("vault-reconcile")
    assert_equal "ledger_coder", Alpha::Qualifier.infer_role("ledger-coding")
  end

  test "Qualifier infers web coding progression roles" do
    assert_equal "ruby_coder", Alpha::Qualifier.infer_role("ruby-coding")
    assert_equal "frontend_coder", Alpha::Qualifier.infer_role("frontend-coding")
    assert_equal "hotwire_coder", Alpha::Qualifier.infer_role("hotwire-coding")
  end

end
