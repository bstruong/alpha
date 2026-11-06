# frozen_string_literal: true

require "test_helper"

class QualifierTest < AlphaTest
  def summary_with(tasks:, scenario: "qwen36-daily")
    {
      "scenario" => scenario,
      "tasks" => tasks
    }
  end

  def task(name:, kind:, pass_at_1:, pass: nil)
    {
      "name" => name,
      "kind" => kind,
      "pass_at_1" => pass_at_1,
      "pass" => pass.nil? ? pass_at_1 : pass
    }
  end

  test "repaired gate does not satisfy gate Pass@1 even when final pass is true" do
    summary = summary_with(
      tasks: [
        task(name: "gate-hello", kind: "gate", pass_at_1: false, pass: true),
        task(name: "gate-boot", kind: "gate", pass_at_1: true),
        task(name: "empty-card", kind: "graded", pass_at_1: true),
        task(name: "spec-wins", kind: "graded", pass_at_1: true),
        task(name: "library-cache", kind: "graded", pass_at_1: true),
        task(name: "audit-three", kind: "graded", pass_at_1: true),
        task(name: "once-only", kind: "graded", pass_at_1: true),
        task(name: "erase-account", kind: "graded", pass_at_1: true)
      ]
    )

    verdict = Alpha::Qualifier.evaluate(summary, scenario: Alpha::Scenario.load("qwen36-daily"))
    refute verdict.qualified
    assert_in_delta (1.0 / 2.0), verdict.gate_pass_at_1, 0.001
    assert_match(/gate Pass@1/, verdict.reason)
  end

  test "scoped-coding uses scenario graded threshold of 0.80" do
    summary = summary_with(
      scenario: "scoped-coding",
      tasks: [
        task(name: "audit-role-escalation", kind: "graded", pass_at_1: true),
        task(name: "audit-book-destroy", kind: "graded", pass_at_1: true),
        task(name: "audit-sql-like-escape", kind: "graded", pass_at_1: false)
      ]
    )

    verdict = Alpha::Qualifier.evaluate(summary, scenario: Alpha::Scenario.load("scoped-coding"))
    refute verdict.qualified
    assert_equal "scoped_coder", verdict.role
    assert_in_delta (2.0 / 3.0), verdict.graded_pass_at_1, 0.001
    assert_equal 0.80, verdict.graded_threshold
    assert_match(/graded Pass@1/, verdict.reason)
  end

  test "pii-scrubbing uses scenario graded threshold of 0.90" do
    summary = summary_with(
      scenario: "pii-scrubbing",
      tasks: [
        task(name: "scrub-ssn-email", kind: "graded", pass_at_1: false)
      ]
    )

    verdict = Alpha::Qualifier.evaluate(summary, scenario: Alpha::Scenario.load("pii-scrubbing"))
    refute verdict.qualified
    assert_equal "sanitizer", verdict.role
    assert_equal 0.0, verdict.graded_pass_at_1
    assert_equal 0.90, verdict.graded_threshold
  end

  test "extractor qualifies when graded Pass@1 meets 0.90 and no gates" do
    summary = summary_with(
      scenario: "ocr-extraction",
      tasks: [
        task(name: "extract-receipt", kind: "graded", pass_at_1: true)
      ]
    )

    verdict = Alpha::Qualifier.evaluate(summary, scenario: Alpha::Scenario.load("ocr-extraction"))
    assert verdict.qualified
    assert_equal "extractor", verdict.role
    assert_equal 1.0, verdict.gate_pass_at_1
    assert_equal 1.0, verdict.graded_pass_at_1
    assert_nil verdict.reason
  end
end
