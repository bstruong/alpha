# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

class GemAndShapeupTest < AlphaTest
  def setup
    Alpha.reset_config!
  end

  def teardown
    Alpha.reset_config!
  end

  test "Alpha::Configuration defaults to Dir.pwd and allows workspace redirection" do
    assert_equal Dir.pwd, Alpha.config.root
    assert_equal File.join(Dir.pwd, "scenarios"), Alpha.config.scenarios_dir
    assert_equal File.join(Dir.pwd, "results"), Alpha.config.results_dir
    assert_equal File.join(Dir.pwd, "reports"), Alpha.config.reports_dir

    Dir.mktmpdir("alpha_test_workspace") do |tmpdir|
      Alpha.configure do |c|
        c.root = tmpdir
      end

      assert_equal tmpdir, Alpha.config.root
      assert_equal File.join(tmpdir, "scenarios"), Alpha.config.scenarios_dir
      assert_equal File.join(tmpdir, "results"), Alpha.config.results_dir
      assert_equal File.join(tmpdir, "reports"), Alpha.config.reports_dir
    end
  end

  test "Grader and Executor registries resolve standard types and custom classes" do
    # Built-in grader resolution
    assert_instance_of Alpha::Grader::MinitestFile, Alpha::Grader.resolve(nil)
    assert_instance_of Alpha::Grader::PatternDeny, Alpha::Grader.resolve("pattern_deny")
    assert_instance_of Alpha::Grader::JsonSchema, Alpha::Grader.resolve("json_schema")
    assert_instance_of Alpha::Grader::RSpecSuite, Alpha::Grader.resolve("rspec_suite")
    assert_instance_of Alpha::Grader::AstDeny, Alpha::Grader.resolve("ast_deny")

    # Custom grader registration
    custom_grader = Class.new(Alpha::Grader::Base)
    Alpha::Grader.register("custom_rubocop", custom_grader)
    assert_instance_of custom_grader, Alpha::Grader.resolve("custom_rubocop")

    # Built-in executor resolution
    assert_instance_of Alpha::Executor::PiRpc, Alpha::Executor.resolve(nil)
    assert_instance_of Alpha::Executor::OpenAIChatCompletions, Alpha::Executor.resolve("openai")

    # Custom executor registration
    custom_executor = Class.new(Alpha::Executor::Base)
    Alpha::Executor.register("custom_cloud", custom_executor)
    assert_instance_of custom_executor, Alpha::Executor.resolve("custom_cloud")
  end

  test "AstDeny detects forbidden Float constant in Ruby source code" do
    grader = Alpha::Grader::AstDeny.new
    task = Struct.new(:denied_constants, :deny_float?).new(["Float"], true)

    Dir.mktmpdir("ast_deny_test") do |tmpdir|
      sandbox = Struct.new(:path).new(tmpdir)

      # 1. Failing code containing Float
      failing_file = File.join(tmpdir, "calc.rb")
      File.write(failing_file, "result = Float(10) / 3.0")

      res = grader.call(sandbox: sandbox, task: task)
      refute res.pass
      assert_equal 1, res.detail[:violations].size
      assert_equal "Float", res.detail[:violations].first[:token]

      # 2. Passing code without Float
      File.write(failing_file, "result = Rational(10, 3)")
      res_ok = grader.call(sandbox: sandbox, task: task)
      assert res_ok.pass
      assert_empty res_ok.detail[:violations]
    end
  end

  test "FixtureImporter ingests omega.failure_export.v1, sanitizes secrets, and writes draft task" do
    Dir.mktmpdir("fixture_import_test") do |tmpdir|
      Alpha.configure { |c| c.root = tmpdir }

      export_payload = {
        "schema" => "omega.failure_export.v1",
        "omega_session_id" => "8f3c1234-abcd-5678-ef01-999988887777",
        "model_id" => "qwen36-coder-hybrid",
        "prompt_preset" => "omega-default",
        "repo_fingerprint" => {
          "url" => "git@github.com:bstruong/saber.git",
          "sha" => "abc1234",
          "dirty" => false
        },
        "initial_prompt" => "Fix reminder calculation. Use API_KEY: secret_token_12345678 and email operator@example.com",
        "follow_ups" => ["Also check user with SSN 123-45-6789"],
        "steers" => ["Please do not touch db/schema.rb"],
        "artifacts" => [
          { "path" => "app/models/reminder.rb", "action" => "modified" }
        ],
        "exit_reason" => "grader_local_rails_test_failed",
        "operator_notes" => "Failed on corner case."
      }

      export_file = File.join(tmpdir, "omega_export.json")
      File.write(export_file, JSON.pretty_generate(export_payload))

      res = Alpha::FixtureImporter.import(export_file)
      assert_equal "regression-8f3c1234", res[:slug]
      assert_equal "draft_needs_grader", res[:status]
      assert File.directory?(res[:task_dir])

      # Verify instruction file was created and secrets were scrubbed
      instruction_path = File.join(res[:task_dir], "instruction.md")
      assert File.file?(instruction_path)
      content = File.read(instruction_path)

      refute_includes content, "secret_token_12345678"
      refute_includes content, "operator@example.com"
      refute_includes content, "123-45-6789"
      assert_includes content, "[REDACTED]"

      # Verify task metadata
      task_yml_path = File.join(res[:task_dir], "task.yml")
      assert File.file?(task_yml_path)
      meta = YAML.safe_load_file(task_yml_path)
      assert_equal "regression-8f3c1234", meta["name"]
      assert_equal "omega", meta["origin"]
      assert_equal "draft_needs_grader", meta["status"]

      # Verify scenario manifest registration
      manifest_path = File.join(tmpdir, "scenarios", "omega_regressions", "scenario.yml")
      assert File.file?(manifest_path)
      manifest = YAML.safe_load_file(manifest_path)
      assert_includes manifest["tasks"], "regression-8f3c1234"
    end
  end

  test "Alpha::FixtureImporter ingests native Pi JSONL session transcripts and redacts secrets" do
    Dir.mktmpdir do |tmpdir|
      Alpha.configure { |c| c.root = tmpdir }

      pi_session_file = File.join(tmpdir, "2026-10-23_01a16710.jsonl")
      lines = [
        JSON.generate({ "type" => "session", "version" => 3, "id" => "01a16710-034c-7310-9ca3-d044fce81c8e", "cwd" => "/tmp/app" }),
        JSON.generate({ "type" => "model_change", "id" => "m1", "provider" => "openai-compatible", "modelId" => "qwen36-coder-hybrid" }),
        JSON.generate({ "type" => "message", "id" => "msg1", "message" => { "role" => "system", "content" => "guardrails" } }),
        JSON.generate({
          "type" => "message",
          "id" => "msg2",
          "message" => {
            "role" => "user",
            "content" => [
              { "type" => "text", "text" => "Fix authentication with api_key=super_secret_pi_key_9999 and contact admin@workstation.local" }
            ]
          }
        }),
        JSON.generate({
          "type" => "message",
          "id" => "msg3",
          "message" => {
            "role" => "user",
            "content" => "Also ensure SSN 987-65-4321 is not printed in logs"
          }
        })
      ]
      File.write(pi_session_file, lines.join("\n") + "\n")

      res = Alpha::FixtureImporter.import(pi_session_file)

      assert_equal "regression-pi-01a16710", res[:slug]
      assert_equal "pi_session", res[:origin]
      assert_equal "draft_needs_grader", res[:status]
      assert File.directory?(res[:task_dir])

      # Verify instruction file was created and secrets were scrubbed
      instruction_path = File.join(res[:task_dir], "instruction.md")
      assert File.file?(instruction_path)
      content = File.read(instruction_path)

      refute_includes content, "super_secret_pi_key_9999"
      refute_includes content, "admin@workstation.local"
      refute_includes content, "987-65-4321"
      assert_includes content, "[REDACTED]"
      assert_includes content, "Operator Follow-ups"

      # Verify task metadata
      task_yml_path = File.join(res[:task_dir], "task.yml")
      assert File.file?(task_yml_path)
      meta = YAML.safe_load_file(task_yml_path)
      assert_equal "regression-pi-01a16710", meta["name"]
      assert_equal "pi_session", meta["origin"]
      assert_equal "01a16710-034c-7310-9ca3-d044fce81c8e", meta["session_id"]
      assert_equal "qwen36-coder-hybrid", meta["failed_model"]
      assert_equal "/tmp/app", meta["cwd"]
      assert_equal "draft_needs_grader", meta["status"]

      # Verify workstation_regressions scenario manifest
      manifest_path = File.join(tmpdir, "scenarios", "workstation_regressions", "scenario.yml")
      assert File.file?(manifest_path)
      manifest = YAML.safe_load_file(manifest_path)
      assert_equal "workstation_regressions", manifest["id"]
      assert_includes manifest["tasks"], "regression-pi-01a16710"
    end
  end

  test "alpha.gemspec packages strictly mechanism files and excludes private homelab artifacts" do
    gemspec_path = File.expand_path("../alpha.gemspec", __dir__)
    spec = Gem::Specification.load(gemspec_path)

    assert_equal "alpha-eval", spec.name
    assert_equal Alpha::VERSION, spec.version.to_s
    assert_empty spec.runtime_dependencies

    # Verify positive allowlist exclusion
    files = spec.files
    assert_includes files, "bin/alpha"
    assert_includes files, "lib/alpha.rb"
    assert_includes files, "lib/alpha/configuration.rb"

    # Must NOT include private scenarios or homelab models
    refute(files.any? { |f| f.start_with?("scenarios/") })
    refute(files.any? { |f| f.start_with?("engine/") })
    refute(files.any? { |f| f.start_with?("results/") })
    refute(files.any? { |f| f.start_with?("reports/") })
    refute(files.any? { |f| f.start_with?("qualifications/") })
  end
end
