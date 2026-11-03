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

  test "AstDeny enforces denied_keywords, denied_defs, required_calls, and vacuous Minitest assertions" do
    grader = Alpha::Grader::AstDeny.new
    task = Struct.new(:denied_constants, :denied_keywords, :denied_defs, :required_calls).new(
      [],
      [ "rescue" ],
      [ "has_helmet?" ],
      [ "dig", "method_missing" ]
    )

    Dir.mktmpdir("ast_structural_test") do |tmpdir|
      sandbox = Struct.new(:path).new(tmpdir)
      FileUtils.mkdir_p(File.join(tmpdir, "lib"))
      FileUtils.mkdir_p(File.join(tmpdir, "test"))

      # 1. Failing code: uses `rescue`, defines hardcoded `def has_helmet?`, omits `method_missing`, and has vacuous `assert true,`
      File.write(File.join(tmpdir, "lib", "gear.rb"), <<~RUBY)
        class Gear
          def lookup(data, idx)
            data.dig(:items)[idx] rescue nil
          end

          def has_helmet?
            true
          end
        end
      RUBY
      File.write(File.join(tmpdir, "test", "gear_test.rb"), <<~RUBY)
        class GearTest
          def test_loadout
            assert true, Gear.new.has_helmet?
          end
        end
      RUBY

      res = grader.call(sandbox: sandbox, task: task)
      refute res.pass
      reasons = res.detail[:violations].map { |v| v[:reason] }
      assert(reasons.any? { |r| r.include?("Denied keyword rescue found") })
      assert(reasons.any? { |r| r.include?("Denied method definition `def has_helmet?` found") })
      assert(reasons.any? { |r| r.include?("Required call/mechanism `method_missing` was not used") })
      assert(reasons.any? { |r| r.include?("Vacuous Minitest assertion `assert true, expr`") })

      # 2. Passing code: uses `dig` and `method_missing`, no `rescue`, no hardcoded `has_helmet?`, valid assertion
      File.write(File.join(tmpdir, "lib", "gear.rb"), <<~RUBY)
        class Gear
          def lookup(data, idx)
            data.dig(:items, idx)
          end

          def method_missing(name, *args)
            name.to_s.start_with?("has_") ? true : super
          end
        end
      RUBY
      File.write(File.join(tmpdir, "test", "gear_test.rb"), <<~RUBY)
        class GearTest
          def test_loadout
            assert Gear.new.has_helmet?
          end
        end
      RUBY

      res_ok = grader.call(sandbox: sandbox, task: task)
      assert res_ok.pass, "Expected AstDeny to pass, got: #{res_ok.detail.inspect}"
      assert_empty res_ok.detail[:violations]
    end
  end

  test "MinitestFile supports pure-Ruby Rakefile projects and verify_test_fails_on_seed mutation checks" do
    grader = Alpha::Grader::MinitestFile.new

    Dir.mktmpdir("pure_ruby_minitest") do |tmpdir|
      app_dir = File.join(tmpdir, "app")
      seeded_dir = File.join(tmpdir, "seeded")
      FileUtils.mkdir_p(File.join(app_dir, "lib"))
      FileUtils.mkdir_p(File.join(app_dir, "test"))

      File.write(File.join(app_dir, "Rakefile"), <<~RUBY)
        task :test do
          Dir.glob("test/*_test.rb").sort.each do |file|
            sh RbConfig.ruby, "-Ilib:test", file
          end
        end
      RUBY

      # Seed has a buggy counter that resets to 1 on every instance
      File.write(File.join(app_dir, "lib", "counter.rb"), <<~RUBY)
        class Counter
          def self.count
            1
          end
        end
      RUBY
      File.write(File.join(app_dir, "test", "counter_test.rb"), <<~RUBY)
        require "minitest/autorun"
        require "counter"

        class CounterTest < Minitest::Test
          def test_count
            assert_equal 1, Counter.count
          end
        end
      RUBY

      sandbox = Alpha::Sandbox.new(path: app_dir, work_dir: tmpdir, seeded_path: seeded_dir)
      sandbox.snapshot_seeded!

      task = Struct.new(:verifier_path, :stable_except, :verify_test_fails_on_seed?).new(nil, [], true)

      # Case 1: Agent fixes code and updates test, but test still only checks `1` (passes on buggy seed!)
      File.write(File.join(app_dir, "test", "counter_test.rb"), <<~RUBY)
        require "minitest/autorun"
        require "counter"

        class CounterTest < Minitest::Test
          def test_count
            # Weak test that still passes on seed
            assert_equal 1, Counter.count
          end
        end
      RUBY
      res_weak = grader.call(sandbox: sandbox, task: task)
      refute res_weak.pass
      assert_equal false, res_weak.detail[:mutation_ok]
      assert_includes res_weak.detail[:mutation_output], "passed against unpatched seed code"

      # Case 2: Agent fixes code AND writes a test that fails on buggy seed (expects 2 after two increments)
      File.write(File.join(app_dir, "lib", "counter.rb"), <<~RUBY)
        class Counter
          class << self
            attr_accessor :count
          end
          def initialize
            self.class.count = (self.class.count || 0) + 1
          end
        end
      RUBY
      File.write(File.join(app_dir, "test", "counter_test.rb"), <<~RUBY)
        require "minitest/autorun"
        require "counter"

        class CounterTest < Minitest::Test
          def test_count
            Counter.count = 0
            Counter.new
            Counter.new
            assert_equal 2, Counter.count
          end
        end
      RUBY

      res_strong = grader.call(sandbox: sandbox, task: task)
      assert res_strong.pass, "Expected strong test + fix to pass, got: #{res_strong.detail.inspect}"
      assert_equal true, res_strong.detail[:mutation_ok]
    end
  end

  test "RSpecSuite supports AST constraint checks and verify_test_fails_on_seed mutation checks" do
    grader = Alpha::Grader::RSpecSuite.new

    Dir.mktmpdir("rspec_suite_mutation") do |tmpdir|
      app_dir = File.join(tmpdir, "app")
      seeded_dir = File.join(tmpdir, "seeded")
      FileUtils.mkdir_p(File.join(app_dir, "bin"))
      FileUtils.mkdir_p(File.join(app_dir, "lib"))
      FileUtils.mkdir_p(File.join(app_dir, "spec"))

      # Minimal bin/rspec stub that runs ruby -Ilib on either the passed spec or all spec/*_spec.rb
      rspec_bin = File.join(app_dir, "bin", "rspec")
      File.write(rspec_bin, <<~RUBY)
        #!/usr/bin/env ruby
        $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
        files = ARGV.empty? ? Dir.glob(File.expand_path("../spec/*_spec.rb", __dir__)) : ARGV
        files.each { |f| load File.expand_path(f) }
      RUBY
      File.chmod(0o755, rspec_bin)

      File.write(File.join(app_dir, "lib", "rule.rb"), <<~RUBY)
        class Rule
          def self.twists
            8
          end
        end
      RUBY
      File.write(File.join(app_dir, "spec", "rule_spec.rb"), <<~RUBY)
        require "rule"
        abort("expected 8") unless Rule.twists == 8
      RUBY

      sandbox = Alpha::Sandbox.new(path: app_dir, work_dir: tmpdir, seeded_path: seeded_dir)
      sandbox.snapshot_seeded!

      task = Struct.new(:verifier_path, :stable_except, :verify_test_fails_on_seed?, :required_calls).new(
        nil, [], true, [ "with" ]
      )

      # Case 1: Weak spec passes on unpatched seed AND missing required_calls `with`
      File.write(File.join(app_dir, "spec", "rule_spec.rb"), <<~RUBY)
        require "rule"
        # Weak check that still passes on unpatched seed
        abort("expected 8") unless Rule.twists == 8
      RUBY
      res_weak = grader.call(sandbox: sandbox, task: task)
      refute res_weak.pass
      assert_equal false, res_weak.detail[:mutation_ok]
      assert_includes res_weak.detail[:mutation_output], "passed against unpatched seed code"
      assert(res_weak.detail[:violations].any? { |v| v[:reason].include?("Required call/mechanism `with`") })

      # Case 2: Strong spec fails on unpatched seed (expects 10) AND code uses `.with`
      File.write(File.join(app_dir, "lib", "rule.rb"), <<~RUBY)
        RuleData = Data.define(:twists)
        class Rule
          def self.twists
            RuleData.new(twists: 8).with(twists: 10).twists
          end
        end
      RUBY
      File.write(File.join(app_dir, "spec", "rule_spec.rb"), <<~RUBY)
        require "rule"
        abort("expected 10") unless Rule.twists == 10
      RUBY

      res_strong = grader.call(sandbox: sandbox, task: task)
      assert res_strong.pass, "Expected RSpecSuite strong spec + fix to pass, got: #{res_strong.detail.inspect}"
      assert_equal true, res_strong.detail[:mutation_ok]
    end
  end

  test "FixtureImporter ingests alpha.failure_export.v1, sanitizes secrets, and writes draft task" do
    Dir.mktmpdir("fixture_import_test") do |tmpdir|
      Alpha.configure { |c| c.root = tmpdir }

      export_payload = {
        "schema" => "alpha.failure_export.v1",
        "session_id" => "8f3c1234-abcd-5678-ef01-999988887777",
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
      assert_equal "failure_export", meta["origin"]
      assert_equal "draft_needs_grader", meta["status"]

      # Verify scenario manifest registration
      manifest_path = File.join(tmpdir, "scenarios", "alpha_regressions", "scenario.yml")
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
