# frozen_string_literal: true

require "test_helper"
require "json"

class PiMonitorTelemetryTest < AlphaTest
  test "read_telemetry parses JSON telemetry file accurately" do
    executor = Alpha::Executor::PiRpc.new
    temp_dir = Dir.mktmpdir("alpha-telemetry-test")
    telemetry_file = File.join(temp_dir, "telemetry.json")
    log_file = File.join(temp_dir, "agent.log")

    File.write(telemetry_file, JSON.pretty_generate({
      "tool_calls" => 12,
      "prompt_tokens" => 3500,
      "completion_tokens" => 420
    }))

    data = executor.send(:read_telemetry, telemetry_file, log_file)
    assert_equal 12, data["tool_calls"]
    assert_equal 3500, data["prompt_tokens"]
    assert_equal 420, data["completion_tokens"]
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end

  test "read_telemetry parses fallback agent log when telemetry file missing" do
    executor = Alpha::Executor::PiRpc.new
    temp_dir = Dir.mktmpdir("alpha-telemetry-test")
    log_file = File.join(temp_dir, "agent.log")

    File.write(log_file, <<~LOG)
      [Qwen-35B] 🛠️ Executing: read app/models/user.rb
      [Qwen-35B] 🛠️ Executing: edit app/models/user.rb
      {"prompt_tokens": 1500, "completion_tokens": 120}
    LOG

    data = executor.send(:read_telemetry, File.join(temp_dir, "missing.json"), log_file)
    assert_equal 2, data["tool_calls"]
    assert_equal 1500, data["prompt_tokens"]
    assert_equal 120, data["completion_tokens"]
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end
