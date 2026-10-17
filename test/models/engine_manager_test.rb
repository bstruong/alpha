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
