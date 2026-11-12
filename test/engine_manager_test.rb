# frozen_string_literal: true

require "test_helper"

class EngineManagerTest < AlphaTest
  test "initializes as HTTP client with default base URL" do
    mgr = Alpha::Engine::Manager.new(base_url: Alpha::Engine::Manager::DEFAULT_BASE_URL)
    assert_equal "http://127.0.0.1:8080/v1", mgr.base_url
    assert_equal "http://127.0.0.1:8080", mgr.server_root_url
  end

  test "up and lease raise ops hint pointing at homelab-k3s" do
    mgr = Alpha::Engine::Manager.new
    err = assert_raises(RuntimeError) { mgr.up(preset: "qwen36-coder-hybrid") }
    assert_match(/jarvis-session/, err.message)
    assert_match(/jarvis-up/, err.message)

    err2 = assert_raises(RuntimeError) { mgr.acquire_lease!(holder: "test") }
    assert_match(/jarvis-session/, err2.message)
  end

  test "InferenceTarget still exposes wake! sleep! manager" do
    target = Alpha::InferenceTarget.new(
      base_url: "http://127.0.0.1:8080/v1",
      model_id: "qwen36-coder-hybrid",
      engine_preset: "qwen36-coder-hybrid"
    )

    assert_respond_to target, :wake!
    assert_respond_to target, :sleep!
    assert_instance_of Alpha::Engine::Manager, target.manager
  end
end
