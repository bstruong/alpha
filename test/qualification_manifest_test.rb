# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "time"

class QualificationManifestTest < AlphaTest
  def shipping_fixture(model_id:, role:, pass_at_1: 1.0)
    now = Time.now.utc
    {
      "schema" => "alpha.qualification.v2",
      "max_rung" => "L1",
      "ceiling_rung" => "L2",
      "credit_mean" => pass_at_1,
      "ship_skills" => [],
      "failure_class_histogram" => { "none" => 1 },
      "model_id" => model_id,
      "engine_preset" => model_id,
      "prompt_preset" => "default",
      "role" => role,
      "scenario_id" => "#{role}-smoke",
      "pass_at_1" => pass_at_1,
      "report_uri" => "reports/#{model_id}__#{role}.md",
      "qualified_at" => now.iso8601,
      "expires_at" => (now + (90 * 24 * 60 * 60)).iso8601
    }
  end

  def with_qual_dir
    Dir.mktmpdir("alpha_qual_test") do |tmpdir|
      fixtures = [
        ["qwen36-coder-hybrid", "coder"],
        ["gemma4-4b", "triager"],
        ["qwen25-coder-14b", "sanitizer"],
        ["qwen25-coder-14b", "extractor"],
        ["glm47-reap", "coder"],
        ["glm47-reap", "triager"],
        ["glm47-reap", "sanitizer"],
        ["glm47-reap", "extractor"],
        ["gemma4-12b", "triager"],
        ["gemma4-27b", "triager"]
      ]
      fixtures.each do |model_id, role|
        name = "#{model_id}__#{role}__shipping.json"
        File.write(
          File.join(tmpdir, name),
          JSON.pretty_generate(shipping_fixture(model_id: model_id, role: role)) + "\n"
        )
      end
      yield tmpdir
    end
  end

  test "loads active qualifications and generates manifest" do
    with_qual_dir do |tmpdir|
      items = Alpha::QualificationManifest.active(tmpdir)
      assert items.size >= 10, "Expected at least 10 active qualifications, got #{items.size}"

      roles = items.map { |q| q["role"] }.uniq
      assert_includes roles, "coder"
      assert_includes roles, "triager"
      assert_includes roles, "sanitizer"
      assert_includes roles, "extractor"

      manifest = Alpha::QualificationManifest.generate(tmpdir)
      assert_equal "alpha.qualification_manifest.v2", manifest["schema"]
      assert_equal "qwen36-coder-hybrid", manifest["roles"]["coder"]["primary_model"]
      assert_equal "qwen36-coder-hybrid", manifest["roles"]["triager"]["primary_model"]
      assert_equal "gemma4-4b", manifest["roles"]["sanitizer"]["primary_model"]
      assert_equal "qwen36-coder-hybrid", manifest["roles"]["extractor"]["primary_model"]
      assert_equal "L1", manifest["roles"]["coder"]["qualified_models"].first["max_rung"]
    end
  end

  test "exports qualifications and manifest to destination directory" do
    with_qual_dir do |source|
      Dir.mktmpdir("alpha_export_test") do |tmpdir|
        copied = Alpha::QualificationManifest.export(tmpdir, source)
        assert_includes copied, "manifest.json"
        assert_includes copied, "qwen36-coder-hybrid__coder__shipping.json"
        assert_includes copied, "gemma4-4b__triager__shipping.json"

        manifest_file = File.join(tmpdir, "manifest.json")
        assert File.file?(manifest_file)
        manifest = JSON.parse(File.read(manifest_file))
        assert_equal "alpha.qualification_manifest.v2", manifest["schema"]
      end
    end
  end

  test "ignores legacy v1 qualification artifacts" do
    Dir.mktmpdir("alpha_qual_v1") do |tmpdir|
      File.write(
        File.join(tmpdir, "legacy__coder__shipping.json"),
        JSON.pretty_generate(shipping_fixture(model_id: "legacy", role: "coder").merge("schema" => "alpha.qualification.v1")) + "\n"
      )
      assert_empty Alpha::QualificationManifest.load_all(tmpdir)
    end
  end

  test "excludes failed qualifications from active set and generated manifest" do
    Dir.mktmpdir("alpha_qual_failed") do |tmpdir|
      File.write(
        File.join(tmpdir, "glm47-reap__coder__shipping.json"),
        JSON.pretty_generate(shipping_fixture(model_id: "glm47-reap", role: "coder").merge("qualified" => true)) + "\n"
      )
      File.write(
        File.join(tmpdir, "glm47-reap__sanitizer__shipping.json"),
        JSON.pretty_generate(
          shipping_fixture(model_id: "glm47-reap", role: "sanitizer", pass_at_1: 0.0).merge(
            "qualified" => false,
            "reason" => "graded Pass@1 0.00 < 0.90"
          )
        ) + "\n"
      )

      active = Alpha::QualificationManifest.active(tmpdir)
      assert_equal 1, active.size
      assert_equal "coder", active.first["role"]

      manifest = Alpha::QualificationManifest.generate(tmpdir)
      assert manifest["roles"].key?("coder")
      refute manifest["roles"].key?("sanitizer")
    end
  end
end

