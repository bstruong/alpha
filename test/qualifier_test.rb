# frozen_string_literal: true

require "test_helper"

class QualifierTest < AlphaTest
  def summary_with(tasks:, scenario: "qwen36-daily", prompt_preset: "shipping", **extra)
    {
      "scenario" => scenario,
      "prompt_preset" => prompt_preset,
      "suite_complete" => true,
      "dry_run" => false,
      "qualification_eligible" => true,
      "tasks" => tasks
    }.merge(extra.transform_keys(&:to_s))
  end

  def task(name:, kind:, pass_at_1:, pass: nil, skill: nil, rung: nil, trial: 1)
    {
      "name" => name,
      "kind" => kind,
      "skill" => skill,
      "rung" => rung,
      "trial" => trial,
      "trial_id" => "#{name}/trial-#{trial}",
      "pass_at_1" => pass_at_1,
      "pass" => pass.nil? ? pass_at_1 : pass,
      "scored" => true,
      "invalid" => false
    }
  end

  def qwen36_shipping_tasks(overrides = {})
    defaults = {
      "gate-hello" => { kind: "gate", skill: "agent_basics", rung: "L0", pass_at_1: true },
      "gate-boot" => { kind: "gate", skill: "agent_basics", rung: "L0", pass_at_1: true },
      "gate-edit" => { kind: "gate", skill: "rails_model_fix", rung: "L1", pass_at_1: true },
      "empty-card" => { kind: "graded", skill: "rails_model_edge", rung: "L2", pass_at_1: true },
      "spec-wins" => { kind: "graded", skill: "rails_spec_priority", rung: "L2", pass_at_1: true },
      "library-cache" => { kind: "graded", skill: "rails_caching", rung: "L2", pass_at_1: true },
      "once-only" => { kind: "graded", skill: "rails_callbacks", rung: "L2", pass_at_1: true },
      "erase-account" => { kind: "graded", skill: "rails_data_lifecycle", rung: "L2", pass_at_1: true }
    }
    defaults.merge(overrides).map do |name, attrs|
      task(name: name, **attrs)
    end
  end

  test "first-attempt fail does not qualify even when final pass would have been true" do
    summary = summary_with(
      tasks: qwen36_shipping_tasks(
        "gate-hello" => { kind: "gate", skill: "agent_basics", rung: "L0", pass_at_1: false, pass: true }
      )
    )

    verdict = Alpha::Qualifier.evaluate(summary, scenario: Alpha::Scenario.load("qwen36-daily"))
    refute verdict.qualified
    assert_in_delta (2.0 / 3.0), verdict.gate_pass_at_1, 0.001
    assert_match(/gate Pass@1/, verdict.reason)
    assert_equal "none", verdict.routing_authority
  end

  test "scoped-coding uses scenario graded threshold of 0.80" do
    summary = summary_with(
      scenario: "scoped-coding",
      tasks: [
        task(name: "recipe-sql-like-escape", kind: "graded", skill: "rails_security", rung: "L0", pass_at_1: true),
        task(name: "audit-role-escalation", kind: "graded", skill: "rails_security", rung: "L1", pass_at_1: true),
        task(name: "audit-book-destroy", kind: "graded", skill: "rails_security", rung: "L1", pass_at_1: true),
        task(name: "audit-sql-like-escape", kind: "graded", skill: "rails_security", rung: "L1", pass_at_1: false)
      ]
    )

    verdict = Alpha::Qualifier.evaluate(summary, scenario: Alpha::Scenario.load("scoped-coding"))
    refute verdict.qualified
    assert_equal "scoped_coder", verdict.role
    assert_in_delta (3.0 / 4.0), verdict.graded_pass_at_1, 0.001
    assert_equal 0.80, verdict.graded_threshold
    assert_match(/graded Pass@1/, verdict.reason)
  end

  test "pii-scrubbing uses scenario graded threshold of 0.90" do
    summary = summary_with(
      scenario: "pii-scrubbing",
      tasks: [
        task(name: "scrub-named-spans", kind: "graded", skill: "pii_scrub", rung: "L0", pass_at_1: true),
        task(name: "scrub-ssn-email", kind: "graded", skill: "pii_scrub", rung: "L1", pass_at_1: false)
      ]
    )

    verdict = Alpha::Qualifier.evaluate(summary, scenario: Alpha::Scenario.load("pii-scrubbing"))
    refute verdict.qualified
    assert_equal "sanitizer", verdict.role
    assert_in_delta 0.5, verdict.graded_pass_at_1, 0.001
    assert_equal 0.90, verdict.graded_threshold
  end

  test "extractor qualifies when graded First-attempt meets 0.90 and no gates" do
    summary = summary_with(
      scenario: "ocr-extraction",
      tasks: [
        task(name: "extract-receipt-template", kind: "graded", skill: "ocr_extract", rung: "L0", pass_at_1: true),
        task(name: "extract-receipt", kind: "graded", skill: "ocr_extract", rung: "L1", pass_at_1: true)
      ]
    )

    verdict = Alpha::Qualifier.evaluate(summary, scenario: Alpha::Scenario.load("ocr-extraction"))
    assert verdict.qualified
    assert_equal "extractor", verdict.role
    assert_equal 1.0, verdict.gate_pass_at_1
    assert_equal 1.0, verdict.graded_pass_at_1
    assert_nil verdict.reason
    assert_equal "none", verdict.routing_authority
  end

  test "infer_role maps ikigai/crm scenario ids to crm_ops" do
    assert_equal "crm_ops", Alpha::Qualifier.infer_role("ikigai-dot")
    assert_equal "crm_ops", Alpha::Qualifier.infer_role("crm-assist")
  end

  test "all-invalid suite does not vacuous-qualify" do
    summary = summary_with(
      scenario: "email-triage",
      tasks: [
        {
          "name" => "triage-fill-template",
          "kind" => "graded",
          "skill" => "triage_priority",
          "pass_at_1" => false,
          "invalid" => true,
          "failure_class" => "infra",
          "trial" => 1,
          "trial_id" => "triage-fill-template/trial-1"
        }
      ]
    )

    verdict = Alpha::Qualifier.evaluate(summary, scenario: Alpha::Scenario.load("email-triage"))
    refute verdict.qualified
    assert_match(/infrastructure-invalid|incomplete expected task set|no scored tasks/, verdict.reason)
    assert_in_delta 0.0, verdict.graded_pass_at_1, 0.001
  end

  test "dry-run and partial suites are rejected" do
    dry = summary_with(tasks: qwen36_shipping_tasks, dry_run: true)
    refute Alpha::Qualifier.evaluate(dry, scenario: Alpha::Scenario.load("qwen36-daily")).qualified

    partial = summary_with(tasks: qwen36_shipping_tasks, suite_complete: false)
    verdict = Alpha::Qualifier.evaluate(partial, scenario: Alpha::Scenario.load("qwen36-daily"))
    refute verdict.qualified
    assert_match(/suite_complete=false/, verdict.reason)
  end

  test "incomplete task set and duplicate ids are rejected" do
    incomplete = summary_with(tasks: [ task(name: "gate-hello", kind: "gate", skill: "agent_basics", pass_at_1: true) ])
    verdict = Alpha::Qualifier.evaluate(incomplete, scenario: Alpha::Scenario.load("qwen36-daily"))
    refute verdict.qualified
    assert_match(/incomplete expected task set/, verdict.reason)

    dup = summary_with(
      tasks: qwen36_shipping_tasks + [
        task(name: "gate-hello", kind: "gate", skill: "agent_basics", rung: "L0", pass_at_1: true, trial: 1)
      ]
    )
    # Force duplicate trial_id collision
    dup["tasks"].last["trial_id"] = dup["tasks"].first["trial_id"]
    verdict2 = Alpha::Qualifier.evaluate(dup, scenario: Alpha::Scenario.load("qwen36-daily"))
    refute verdict2.qualified
    assert_match(/duplicate/, verdict2.reason)
  end
end
