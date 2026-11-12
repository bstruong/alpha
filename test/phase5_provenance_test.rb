# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"
require "fileutils"

class Phase5ProvenanceTest < AlphaTest
  def with_results_tmpdir
    Dir.mktmpdir("alpha-phase5") do |tmpdir|
      Alpha.configure do |c|
        c.results_dir = File.join(tmpdir, "results")
        c.reports_dir = File.join(tmpdir, "reports")
        c.qualifications_dir = File.join(tmpdir, "qualifications")
      end
      FileUtils.mkdir_p(Alpha.config.results_dir)
      FileUtils.mkdir_p(Alpha.config.reports_dir)
      yield tmpdir
    ensure
      Alpha.reset_config!
    end
  end

  test "run manifest is created then finalized in the same file" do
    with_results_tmpdir do
      scenario = Alpha::Scenario.load("qwen36-daily", only_task: "gate-hello")
      run_id = "phase5-manifest-demo"
      started = Alpha::RunManifest.create!(run_id, scenario: scenario, seed: scenario.seed)
      assert_equal "alpha.run_manifest.v1", started["schema"]
      assert_equal "started", started["status"]
      path = Alpha::RunManifest.path_for(run_id)
      assert File.file?(path)

      Alpha::RunManifest.record_trial!(run_id, trial: {
        trial_id: "#{run_id}/gate-hello/trial-1",
        task_name: "gate-hello",
        trial: 1,
        seed: scenario.seed
      })

      final = Alpha::RunManifest.finalize!(
        run_id,
        terminal_status: "ok",
        summary_path: nil,
        report_path: nil
      )
      assert_equal "final", final["status"]
      assert_equal "ok", final["terminal_status"]
      assert final["finished_at"]
      assert_equal 1, final["trials"].size
      assert final["artifact_hashes"].key?("run_manifest")
      # Same path finalized in place.
      assert_equal path, Alpha::RunManifest.path_for(run_id)
    end
  end

  test "promotable requires digest pins SHAs clean tree and watchtower job" do
    body = {
      "repositories" => {
        "alpha" => { "commit" => "a" * 40, "dirty" => false, "ref" => "a" * 40 },
        "alpha_lab" => { "commit" => "b" * 40, "dirty" => false, "ref" => "b" * 40 },
        "homelab_k3s" => { "commit" => "c" * 40, "dirty" => false, "ref" => "c" * 40 }
      },
      "runner" => {
        "image" => "registry.example/alpha-runner@sha256:#{'d' * 64}",
        "image_digest" => "sha256:#{'d' * 64}"
      },
      "content" => {
        "scenario_hash" => "sha256:#{'e' * 64}",
        "task_hashes" => [ { "name" => "t", "hash" => "sha256:#{'f' * 64}" } ]
      },
      "graded_host" => { "watchtower_job" => true }
    }
    assert_empty Alpha::Provenance.promotable_blockers(body)
    assert Alpha::Provenance.promotable?(body)

    dirty = Marshal.load(Marshal.dump(body))
    dirty["repositories"]["alpha"]["dirty"] = true
    assert_includes Alpha::Provenance.promotable_blockers(dirty).join, "dirty"

    latest = Marshal.load(Marshal.dump(body))
    latest["runner"]["image"] = "registry.example/alpha-runner:latest"
    assert_includes Alpha::Provenance.promotable_blockers(latest).join, "latest"

    moving = Marshal.load(Marshal.dump(body))
    moving["repositories"]["alpha"]["ref"] = "main"
    moving["repositories"]["alpha"]["commit"] = "main"
    assert Alpha::Provenance.promotable_blockers(moving).any? { |b| b.include?("SHA") || b.include?("moving") }
  end

  test "report includes provenance evidence links and deterministic re-render" do
    with_results_tmpdir do
      records = [
        {
          run_id: "phase5-report",
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
          trial_id: "phase5-report/gate-hello/trial-1",
          seed: 12_345,
          evidence_uri: "results/runs/phase5-report/gate-hello/trial-1/result.json",
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
      Alpha::RunManifest.create!("phase5-report", seed: 12_345)
      res = Alpha::Report.build(
        "phase5-report",
        scenario: Alpha::Scenario.load("qwen36-daily", only_task: "gate-hello"),
        model_id: "demo",
        prompt_preset: "shipping",
        inference_target: target,
        task_records: records,
        suite_complete: true
      )
      payload = res[:payload]
      assert_equal "alpha.report.v2", payload["schema"]
      assert payload.key?("provenance")
      assert_equal "alpha.provenance.v1", payload.dig("provenance", "schema")
      assert payload.key?("run_manifest_uri")
      assert_includes payload.dig("tasks", 0, "evidence_uri"), "result.json"
      md = File.read(res[:report_path])
      assert_includes md, "## Can do"
      assert_includes md, "## Supporting evidence"
      assert_includes md, "Machine-readable evidence index"
      assert_operator md.index("## Can do"), :<, md.index("## Supporting evidence")

      Alpha::RunManifest.finalize!(
        "phase5-report",
        terminal_status: "ok",
        summary_path: res[:summary_path],
        report_path: res[:report_path],
        summary_payload: payload
      )
      manifest = Alpha::RunManifest.load("phase5-report")
      md1 = Alpha::Report.render_from_bundle(payload, run_manifest: manifest)
      md2 = Alpha::Report.render_from_bundle(payload, run_manifest: manifest)
      assert_equal md1, md2

      bundle = Alpha::RunManifest.sanitized_bundle("phase5-report")
      refute bundle.dig("provenance", "repositories", "alpha")&.key?("path")
    end
  end

  test "qualifier fails closed for watchtower promotable without pins" do
    summary = {
      "schema" => "alpha.report.v2",
      "run_id" => "wt-1",
      "scenario" => "qwen36-daily",
      "model_id" => "demo",
      "prompt_preset" => "shipping",
      "suite_complete" => true,
      "dry_run" => false,
      "qualification_eligible" => true,
      "provenance" => {
        "graded_host" => { "watchtower_job" => true },
        "repositories" => {},
        "runner" => {},
        "content" => {}
      },
      "status" => {
        "execution_health" => "ok",
        "gate_status" => "passed",
        "benchmark_verdict" => "pass",
        "statistical_sufficiency" => "single_trial_evidence",
        "qualification_eligible" => true,
        "routing_authority" => "none"
      },
      "aggregate" => { "pass_at_1" => 1.0 },
      "tasks" => [
        {
          "name" => "gate-hello",
          "kind" => "gate",
          "pass_at_1" => true,
          "scored" => true,
          "invalid" => false,
          "credit" => 1.0,
          "rung" => "L0",
          "skill" => "general",
          "trial" => 1
        }
      ]
    }
    # Load only gate-hello by stubbing scenario expectation loosely: use real scenario and accept incomplete task set.
    # Force require_promotable via graded_host.
    scenario = Alpha::Scenario.load("qwen36-daily", profile: "shipping")
    # Expand tasks to match scenario expected set so provenance is the failure reason.
    summary["tasks"] = scenario.tasks.map do |t|
      {
        "name" => t.name,
        "kind" => t.kind,
        "pass_at_1" => true,
        "scored" => true,
        "invalid" => false,
        "credit" => 1.0,
        "rung" => t.rung,
        "skill" => t.skill.to_s.empty? ? "general" : t.skill.to_s,
        "trial" => 1,
        "trial_id" => "wt-1/#{t.name}/1"
      }
    end

    verdict = Alpha::Qualifier.evaluate(summary, scenario: scenario)
    refute verdict.qualified
    assert_match(/provenance/, verdict.reason.to_s)
    assert_equal "none", verdict.routing_authority
  end

  test "sanitize_url redacts private topology" do
    assert_equal "http://redacted.invalid/v1", Alpha::Provenance.sanitize_url("http://ai.watchtower.local/v1")
    assert_equal "http://redacted.invalid/v1", Alpha::Provenance.sanitize_url("http://10.42.0.1/v1")
    assert_equal "https://example.com/v1", Alpha::Provenance.sanitize_url("https://example.com/v1")
  end
end
