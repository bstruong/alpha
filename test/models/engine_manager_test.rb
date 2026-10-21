# frozen_string_literal: true

require "test_helper"

class EngineManagerTest < ActiveSupport::TestCase
  test "initializes with default options" do
    mgr = Alpha::Engine::Manager.new
    assert_equal "alpha", mgr.namespace
    assert_equal "alpha-llama", mgr.deployment
    assert_equal "http://127.0.0.1:8080/v1", mgr.base_url
    assert_equal "http://127.0.0.1:8080", mgr.server_root_url
  end

  test "resolves presets correctly" do
    mgr = Alpha::Engine::Manager.new
    model, al = mgr.send(:resolve_model_and_alias, "glm47-reap")
    assert_includes model, "GLM-4.7"
    assert_includes al, "glm47"

    model_q, al_q = mgr.send(:resolve_model_and_alias, "qwen36-coder-hybrid")
    assert_includes model_q, "Qwen3.6"
    assert_includes al_q, "qwen36-coder"

    assert_raises(ArgumentError) do
      mgr.send(:resolve_model_and_alias, "non-existent-model")
    end
  end

  test "preset_args returns tailored args for each architecture" do
    mgr = Alpha::Engine::Manager.new

    q14 = mgr.preset_args("qwen25-coder-14b")
    assert_includes q14, "/models/qwen2.5-coder-14b-instruct-q4_k_m.gguf"
    assert_includes q14, "16384"
    assert_not_includes q14, "--cpu-moe"
    assert_not_includes q14, "--n-cpu-moe"

    glm = mgr.preset_args("glm47-reap")
    assert_includes glm, "/models/GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf"
    assert_includes glm, "131072"
    assert_includes glm, "--cpu-moe"

    q36 = mgr.preset_args("qwen36-coder-hybrid")
    assert_includes q36, "/models/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"
    assert_includes q36, "262144"
    assert_includes q36, "--n-cpu-moe"

    gemma = mgr.preset_args("gemma4-4b")
    assert_includes gemma, "/models/gemma-4-e4b-it-q4_k_m.gguf"
    assert_includes gemma, "16384"
    assert_not_includes gemma, "--cpu-moe"

    gemma12 = mgr.preset_args("gemma4-12b")
    assert_includes gemma12, "/models/gemma-4-12b-it-q4_k_m.gguf"
    assert_includes gemma12, "16384"
    assert_not_includes gemma12, "--cpu-moe"

    gemma27 = mgr.preset_args("gemma4-27b")
    assert_includes gemma27, "/models/gemma-4-26b-a4b-it-q4_k_m.gguf"
    assert_includes gemma27, "32768"
    assert_includes gemma27, "--cpu-moe"
  end

  test "InferenceTarget provides wake! and sleep! methods" do
    target = Alpha::InferenceTarget.new(
      base_url: "http://127.0.0.1:8080/v1",
      model_id: "qwen36-coder-hybrid",
      engine_preset: "qwen36-coder-hybrid"
    )

    assert_respond_to target, :wake!
    assert_respond_to target, :sleep!
    assert_respond_to target, :metrics
    assert_instance_of Alpha::Engine::Manager, target.manager
  end
end
