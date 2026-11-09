# frozen_string_literal: true

require "test_helper"
require "json"

class Phase3InvariantBaselinesTest < AlphaTest
  test "prompt honors Profile#include_invariant rather than profile.to_s" do
    task_dir = File.expand_path(
      "../scenarios/email-triage/tasks/triage-classify-priority",
      __dir__
    )
    task = Alpha::Task.load(task_dir)
    assert task.invariant, "fixture task needs invariant.md"

    shipping = Alpha::Scenario::Profile.fetch("shipping", "shipping" => {
      "bullet_cap" => true,
      "include_invariant" => false,
      "max_rung" => "L2"
    })
    refute_includes task.prompt(shipping), task.invariant.strip

    oracle = Alpha::Scenario::Profile.fetch("oracle")
    assert_includes task.prompt(oracle), task.invariant.strip

    debug = Alpha::Scenario::Profile.fetch("debug")
    assert_includes task.prompt(debug), task.invariant.strip

    # String "shipping" alone must not inject invariants after Phase 3.
    refute_includes task.prompt("shipping"), task.invariant.strip
  end

  test "Scenario loads oracle and debug profiles" do
    oracle = Alpha::Scenario.load("email-triage", profile: "oracle", only_task: "triage-classify-priority")
    assert_equal "oracle", oracle.profile.name
    assert_equal true, oracle.profile.include_invariant

    debug = Alpha::Scenario.load("email-triage", profile: "debug", only_task: "triage-classify-priority")
    assert_equal "debug", debug.profile.name
    assert_equal true, debug.profile.include_invariant
  end

  test "shipping scenarios default include_invariant false" do
    scenario = Alpha::Scenario.load("qwen36-daily", profile: "shipping", only_task: "gate-hello")
    assert_equal false, scenario.profile.include_invariant
  end

  test "TrialOutcome treats nop missing output as scored failure" do
    out = Alpha::TrialOutcome.classify(
      exit_reason: "nop",
      timed_out: false,
      agent_patch_empty: true,
      grader_detail: { error: "Missing output.txt in sandbox" }
    )
    assert_equal false, out[:invalid]
    assert_equal true, out[:scored]
  end

  test "Qualifier require_baselines fails closed without observed_ok pair" do
    scenario = Alpha::Scenario.load("qwen36-daily", profile: "shipping", only_task: "gate-hello")
    scenario.qualification[:require_baselines] = true

    Dir.mktmpdir("alpha-baseline-gate") do |tmpdir|
      previous_root = Alpha.config.root
      Alpha.configure { |c| c.root = tmpdir }
      summary = {
        "scenario" => "qwen36-daily",
        "prompt_preset" => "shipping",
        "suite_complete" => true,
        "tasks" => [ {
          "name" => "gate-hello",
          "kind" => "gate",
          "trial" => 1,
          "pass_at_1" => true,
          "pass" => true,
          "scored" => true,
          "skill" => "general",
          "rung" => "L0"
        } ],
        "status" => {
          "execution_health" => "ok",
          "gate_status" => "passed",
          "benchmark_verdict" => "pass",
          "statistical_sufficiency" => "not_evaluated"
        }
      }

      verdict = Alpha::Qualifier.evaluate(summary, scenario: scenario, role: "coder")
      refute verdict.qualified
      assert_match(/require_baselines/, verdict.reason)
    ensure
      Alpha.configure { |c| c.root = previous_root }
    end
  end

  test "Qualifier require_baselines accepts matching observed_ok pair" do
    scenario = Alpha::Scenario.load("qwen36-daily", profile: "shipping", only_task: "gate-hello")
    scenario.qualification[:require_baselines] = true

    Dir.mktmpdir("alpha-baseline-ok") do |tmpdir|
      previous_root = Alpha.config.root
      Alpha.configure { |c| c.root = tmpdir }

      base = File.join(tmpdir, "baselines", "qwen36-daily")
      FileUtils.mkdir_p(base)
      key = "abc123__deadbeefcafe"
      common = {
        "scenario_hash" => "abc123",
        "harness_rev" => "deadbeefcafe",
        "observed_ok" => true
      }
      File.write(File.join(base, "oracle-pass__#{key}.json"), JSON.pretty_generate(common.merge("control" => "oracle-pass")))
      File.write(File.join(base, "nop-fail__#{key}.json"), JSON.pretty_generate(common.merge("control" => "nop-fail")))

      skill = scenario.tasks.first.skill.to_s
      skill = "general" if skill.empty?
      summary = {
        "scenario" => "qwen36-daily",
        "prompt_preset" => "shipping",
        "suite_complete" => true,
        "tasks" => [ {
          "name" => "gate-hello",
          "kind" => "gate",
          "trial" => 1,
          "pass_at_1" => true,
          "pass" => true,
          "scored" => true,
          "skill" => skill,
          "rung" => "L0"
        } ],
        "status" => {
          "execution_health" => "ok",
          "gate_status" => "passed",
          "benchmark_verdict" => "pass",
          "statistical_sufficiency" => "not_evaluated"
        }
      }

      verdict = Alpha::Qualifier.evaluate(summary, scenario: scenario, role: "coder")
      assert_nil verdict.reason, verdict.reason
      assert verdict.qualified
    ensure
      Alpha.configure { |c| c.root = previous_root }
    end
  end
end
