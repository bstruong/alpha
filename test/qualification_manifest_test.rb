# frozen_string_literal: true

require "test_helper"

class QualificationManifestTest < AlphaTest
  test "loads active qualifications and generates manifest" do
    items = Alpha::QualificationManifest.active
    assert items.size >= 10, "Expected at least 10 active qualifications, got #{items.size}"

    roles = items.map { |q| q["role"] }.uniq
    assert_includes roles, "coder"
    assert_includes roles, "triager"
    assert_includes roles, "sanitizer"
    assert_includes roles, "extractor"

    manifest = Alpha::QualificationManifest.generate
    assert_equal "alpha.qualification_manifest.v1", manifest["schema"]
    assert_equal "qwen36-coder-hybrid", manifest["roles"]["coder"]["primary_model"]
    assert_equal "gemma4-4b", manifest["roles"]["triager"]["primary_model"]
    assert_equal "qwen25-coder-14b", manifest["roles"]["sanitizer"]["primary_model"]
    assert_equal "qwen25-coder-14b", manifest["roles"]["extractor"]["primary_model"]
  end

  test "exports qualifications and manifest to destination directory" do
    Dir.mktmpdir("omega_export_test") do |tmpdir|
      copied = Alpha::QualificationManifest.export(tmpdir)
      assert_includes copied, "manifest.json"
      assert_includes copied, "qwen36-coder-hybrid__coder__shipping.json"
      assert_includes copied, "gemma4-4b__triager__shipping.json"

      manifest_file = File.join(tmpdir, "manifest.json")
      assert File.file?(manifest_file)
      manifest = JSON.parse(File.read(manifest_file))
      assert_equal "alpha.qualification_manifest.v1", manifest["schema"]
    end
  end
end
