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

      def self.default_harness_dir
        Alpha.config.harness_dir
      end

      attr_reader :harness_dir

      def initialize(harness_dir: nil)
        @harness_dir = harness_dir || self.class.default_harness_dir
      end

      def call(task:, sandbox:, inference_target:, profile: "shipping",
               log_path: nil, telemetry_path: nil, timeout_s: DEFAULT_TIMEOUT,
               max_tool_calls: nil)
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

        resolved_log = log_path || (sandbox.respond_to?(:agent_log_path) ? sandbox.agent_log_path : File.join(sandbox.work_dir, "agent.log"))
        resolved_telemetry = telemetry_path || (sandbox.respond_to?(:agent_telemetry_path) ? sandbox.agent_telemetry_path : File.join(sandbox.work_dir, "telemetry.json"))
        FileUtils.mkdir_p(File.dirname(resolved_log))
        FileUtils.mkdir_p(File.dirname(resolved_telemetry))

        overlay = nil
        begin
          # Fail closed: never spawn an evaluated Pi agent outside the namespace.
          Isolation.require_available!

          overlay = materialize_harness_overlay(inference_target)
          cmd, env = build_command(
            task, sandbox, inference_target, profile, resolved_log, resolved_telemetry,
            runtime_harness_dir: overlay,
            max_tool_calls: max_tool_calls
          )

          read_only = [
            overlay,
            harness_dir,
            File.expand_path("..", __dir__), # lib/alpha/executor (pi_monitor.rb)
            File.dirname(RbConfig.ruby)
          ]
          pi_bin = env["PI_BIN"]
          if pi_bin && !pi_bin.empty?
            # Bind the npm package root (…/pi-harness), not just node_modules/.bin —
            # the shim resolves into node_modules/@… which must be mounted too.
            root = Isolation.pi_package_root(pi_bin)
            read_only << (root && !root.empty? ? root : File.dirname(pi_bin))
          end
          system_prompt = cmd[cmd.index("--append-system-prompt") + 1] rescue nil
          read_only << File.dirname(system_prompt) if system_prompt && File.exist?(system_prompt)

          wrapped_cmd, spawn_env = Isolation.wrap(
            cmd,
            env: env,
            chdir: sandbox.path,
            writable_paths: [ sandbox.path ],
            read_only_paths: read_only,
            network: true
          )

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          pid = Process.spawn(spawn_env, *wrapped_cmd, pgroup: true)
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
          elsif telemetry["tool_budget_exceeded"] || (max_tool_calls && telemetry["tool_calls"] >= max_tool_calls)
            "tool_budget_exceeded"
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
        ensure
          FileUtils.remove_entry(overlay) if overlay && File.directory?(overlay)
        end
      end

      private
        # Per-run harness overlay so Pi uses InferenceTarget's URL instead of
        # the checked-in localhost defaults in models.json / settings.json.
        def materialize_harness_overlay(inference_target)
          overlay = Dir.mktmpdir("alpha-pi-harness-")
          %w[node_modules SYSTEM.md package.json package-lock.json auth.json bin].each do |entry|
            src = File.join(harness_dir, entry)
            next unless File.exist?(src)

            FileUtils.ln_s(src, File.join(overlay, entry))
          end

          models_src = File.join(harness_dir, "models.json")
          models = File.file?(models_src) ? JSON.parse(File.read(models_src)) : { "providers" => {} }
          provider = models.fetch("providers")["openai-compatible"] || {}
          provider = provider.merge(
            "name" => provider["name"] || "Alpha inference",
            "baseUrl" => inference_target.base_url,
            "api" => provider["api"] || "openai-completions",
            "apiKey" => provider["apiKey"] || "ignored",
            "models" => provider["models"] || []
          )
          models["providers"] = (models["providers"] || {}).merge("openai-compatible" => provider)
          File.write(File.join(overlay, "models.json"), JSON.pretty_generate(models) + "\n")

          settings_src = File.join(harness_dir, "settings.json")
          settings = File.file?(settings_src) ? JSON.parse(File.read(settings_src)) : {}
          root = inference_target.server_root_url
          servers = Array(settings.dig("llamaSettings", "servers"))
          if servers.empty?
            servers = [ { "url" => root, "id" => "alpha-runtime", "name" => "Alpha runtime" } ]
          else
            servers = servers.map { |s| s.merge("url" => root) }
          end
          settings["llamaSettings"] = (settings["llamaSettings"] || {}).merge("servers" => servers)
          File.write(File.join(overlay, "settings.json"), JSON.pretty_generate(settings) + "\n")

          overlay
        end

        def build_command(task, sandbox, inference_target, profile, log_path, telemetry_path,
                          runtime_harness_dir:, max_tool_calls: nil)
          prompt_text = task.prompt(profile)
          server_url = inference_target.server_root_url
          openai_base = inference_target.base_url

          base_env = sandbox.respond_to?(:agent_env) ? sandbox.agent_env : sandbox.child_env
          env = base_env.merge(
            "PI_CODING_AGENT_DIR" => runtime_harness_dir,
            "LLAMA_SERVER_URL" => server_url,
            "LLAMA_BASE_URL" => server_url,
            "OPENAI_BASE_URL" => openai_base,
            "OPENAI_API_BASE" => openai_base,
            "OPENAI_API_KEY" => ENV["OPENAI_API_KEY"] || "ignored",
            "PI_BIN" => Alpha.config.pi_bin
          )

          # Shipping and measurement both use Pi; profiles differ via task filter /
          # prompt scaffolding, not via a separate agent binary (miniswen removed).
          monitor_script = File.expand_path("pi_monitor.rb", __dir__)

          system_prompt = if File.file?(File.join(runtime_harness_dir, "SYSTEM.md"))
            File.join(runtime_harness_dir, "SYSTEM.md")
          elsif File.file?(File.join(harness_dir, "SYSTEM.md"))
            File.join(harness_dir, "SYSTEM.md")
          elsif File.file?(File.expand_path("~/.pi/agent/SYSTEM.md"))
            File.expand_path("~/.pi/agent/SYSTEM.md")
          else
            File.join(harness_dir, "SYSTEM.md")
          end
          model_supports_reasoning = !inference_target.model_id.to_s.match?(/14b/i)
          thinking_level = if model_supports_reasoning
            (task.respond_to?(:thinking) && task.thinking) ? task.thinking : "low"
          else
            "off"
          end
          monitor_args = [
            "--log-file", log_path,
            "--telemetry-file", telemetry_path
          ]
          monitor_args.concat(["--max-tool-calls", max_tool_calls.to_s]) if max_tool_calls

          cmd = [
            RbConfig.ruby, monitor_script,
            *monitor_args,
            "--",
            "--mode", "json",
            "-p",
            "--provider", "openai-compatible",
            "--model", inference_target.model_id,
            "--thinking", thinking_level,
            "--no-context-files",
            "--approve",
            "--no-session",
            "--append-system-prompt", system_prompt,
            prompt_text
          ]

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
