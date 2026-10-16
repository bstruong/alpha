# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"

module Alpha
  module Executor
    # Headless Pi execution wrapper using pi-monitor.rb for process supervision,
    # heartbeat logging, and structured telemetry extraction.
    class PiRpc < Base
      DEFAULT_TIMEOUT = 720

      def self.repo_root
        File.expand_path("../../..", __dir__)
      end

      def self.default_harness_dir
        File.join(repo_root, "harness", "pi")
      end

      attr_reader :harness_dir

      def initialize(harness_dir: nil)
        @harness_dir = harness_dir || self.class.default_harness_dir
      end

      def call(task:, sandbox:, inference_target:, profile: "shipping",
               log_path: nil, telemetry_path: nil, timeout_s: DEFAULT_TIMEOUT)
        # gate-boot is a pure test of the unpatched environment, no agent required
        if task.name == "gate-boot"
          return Result.new(
            exit_reason: "skip_boot_check",
            timed_out: false,
            wall_ms: 0,
            tool_calls: 0,
            prompt_tokens: 0,
            completion_tokens: 0,
            log_path: log_path
          )
        end

        resolved_log = log_path || File.join(sandbox.work_dir, "agent.log")
        resolved_telemetry = telemetry_path || File.join(sandbox.work_dir, "telemetry.json")
        FileUtils.mkdir_p(File.dirname(resolved_log))

        cmd, env = build_command(task, sandbox, inference_target, profile, resolved_log, resolved_telemetry)

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        pid = Process.spawn(env, *cmd, chdir: sandbox.path, pgroup: true)
        deadline = start_time + timeout_s
        timed_out = false

        loop do
          _pid, status = Process.wait2(pid, Process::WNOHANG)
          break if status

          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            timed_out = true
            begin
              pgid = Process.getpgid(pid) rescue pid
              Process.kill("-TERM", pgid)
              sleep 1
              Process.kill("-KILL", pgid) if Process.wait2(pid, Process::WNOHANG).nil?
            rescue StandardError
              # Ignore process termination errors
            end
            break
          end
          sleep 0.5
        end

        wall_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

        telemetry = read_telemetry(resolved_telemetry, resolved_log)
        exit_reason = if timed_out
          "timeout"
        else
          telemetry["tool_calls"].positive? ? "completed" : "no_tools_called"
        end

        Result.new(
          exit_reason: exit_reason,
          timed_out: timed_out,
          wall_ms: wall_ms,
          tool_calls: telemetry["tool_calls"],
          prompt_tokens: telemetry["prompt_tokens"],
          completion_tokens: telemetry["completion_tokens"],
          log_path: resolved_log
        )
      end

      private
        def build_command(task, sandbox, inference_target, profile, log_path, telemetry_path)
          prompt_text = task.prompt(profile)
          server_url = inference_target.server_root_url
          openai_base = inference_target.base_url

          env = sandbox.child_env.merge(
            "PI_CODING_AGENT_DIR" => harness_dir,
            "LLAMA_SERVER_URL" => server_url,
            "LLAMA_BASE_URL" => server_url,
            "OPENAI_BASE_URL" => openai_base,
            "OPENAI_API_BASE" => openai_base,
            "OPENAI_API_KEY" => ENV["OPENAI_API_KEY"] || "ignored",
            "PI_BIN" => File.join(harness_dir, "node_modules", ".bin", "pi")
          )

          profile_name = profile.respond_to?(:name) ? profile.name : profile.to_s
          monitor_script = File.join(harness_dir, "bin", "pi-monitor.rb")

          if profile_name == "shipping"
            system_prompt = File.join(harness_dir, "SYSTEM.md")
            cmd = [
              RbConfig.ruby, monitor_script,
              "--log-file", log_path,
              "--telemetry-file", telemetry_path,
              "--",
              "--print",
              "--provider", "openai-compatible",
              "--model", inference_target.model_id,
              "--thinking", "low",
              "--approve",
              "--no-session",
              "--append-system-prompt", system_prompt,
              prompt_text
            ]
          else
            env["BENCH_MODEL"] = inference_target.model_id
            cmd = [ "miniswen", "-p", prompt_text ]
          end

          [ cmd, env ]
        end

        def read_telemetry(telemetry_path, log_path)
          if File.file?(telemetry_path)
            data = JSON.parse(File.read(telemetry_path)) rescue nil
            return data if data.is_a?(Hash)
          end

          tool_calls = 0
          prompt_tokens = 0
          completion_tokens = 0
          if File.file?(log_path)
            File.foreach(log_path) do |line|
              tool_calls += 1 if line.include?("🛠️ Executing:")
              if (m = line.match(/(?:prompt_tokens|promptTokens)["']?\s*:\s*(\d+)/i))
                prompt_tokens += m[1].to_i
              end
              if (m = line.match(/(?:completion_tokens|completionTokens)["']?\s*:\s*(\d+)/i))
                completion_tokens += m[1].to_i
              end
            end
          end

          {
            "tool_calls" => tool_calls,
            "prompt_tokens" => prompt_tokens,
            "completion_tokens" => completion_tokens
          }
        end
    end
  end
end
