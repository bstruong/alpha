# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "uri"

module Alpha
  module Executor
    # Stateless OpenAI-compatible /v1/chat/completions executor.
    # Eliminates agent framework overhead for direct text transformation,
    # PII scrubbing, and structured JSON document extraction.
    class OpenAIChatCompletions < Base
      DEFAULT_TIMEOUT = 60

      def call(task:, sandbox:, inference_target:, profile: "shipping",
               log_path: nil, telemetry_path: nil, timeout_s: DEFAULT_TIMEOUT)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        resolved_log = log_path || File.join(sandbox.work_dir, "agent.log")
        resolved_telemetry = telemetry_path || File.join(sandbox.work_dir, "telemetry.json")
        FileUtils.mkdir_p(File.dirname(resolved_log))

        system_msg = if task.respond_to?(:system_prompt) && task.system_prompt
          task.system_prompt
        else
          "You are a precise, deterministic data processing assistant. Output the requested data directly without deliberation, thinking tags, or markdown fences."
        end

        messages = [
          { "role" => "system", "content" => system_msg },
          { "role" => "user", "content" => task.prompt(profile) }
        ]

        thinking_level = task.respond_to?(:thinking) && task.thinking ? task.thinking.to_s : "none"
        reasoning_budget = case thinking_level
        when "none", "off", "0" then 0
        when "minimal" then 128
        when "low" then 256
        else 0
        end

        payload = {
          "model" => inference_target.model_id,
          "messages" => messages,
          "temperature" => 0.0,
          "seed" => 12345,
          "reasoning_budget" => reasoning_budget,
          "chat_template_kwargs" => { "thinking" => false, "enable_thinking" => false }
        }

        if task.respond_to?(:json_mode?) && task.json_mode?
          payload["response_format"] = { "type" => "json_object" }
        end

        uri = URI.parse("#{inference_target.base_url}/chat/completions")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["Authorization"] = "Bearer #{ENV.fetch("OPENAI_API_KEY", "ignored")}"
        req.body = JSON.generate(payload)

        prompt_tokens = 0
        completion_tokens = 0
        output_content = ""
        timed_out = false
        exit_reason = "completed"

        begin
          res = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: timeout_s) do |http|
            http.request(req)
          end

          if res.is_a?(Net::HTTPSuccess)
            body = JSON.parse(res.body) rescue {}
            output_content = body.dig("choices", 0, "message", "content").to_s
            usage = body["usage"] || {}
            prompt_tokens = usage["prompt_tokens"].to_i
            completion_tokens = usage["completion_tokens"].to_i
          else
            exit_reason = "http_error_#{res.code}"
            output_content = res.body.to_s
          end
        rescue Net::ReadTimeout, Net::OpenTimeout
          timed_out = true
          exit_reason = "timeout"
        rescue StandardError => e
          exit_reason = "error: #{e.message}"
        end

        wall_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

        # Save output artifact in sandbox
        output_path = File.join(sandbox.path, "output.txt")
        File.write(output_path, output_content)

        # Write log and telemetry
        File.write(resolved_log, <<~LOG)
          === OpenAI Chat Completions Request ===
          URI: #{uri}
          Model: #{inference_target.model_id}
          Messages: #{JSON.pretty_generate(messages)}

          === Response (#{exit_reason}) ===
          Wall ms: #{wall_ms}
          Usage: prompt=#{prompt_tokens}, completion=#{completion_tokens}
          Content:
          #{output_content}
        LOG

        File.write(resolved_telemetry, JSON.pretty_generate({
          "tool_calls" => 0,
          "prompt_tokens" => prompt_tokens,
          "completion_tokens" => completion_tokens
        }))

        Result.new(
          exit_reason: exit_reason,
          timed_out: timed_out,
          wall_ms: wall_ms,
          tool_calls: 0,
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          log_path: resolved_log
        )
      end
    end
  end
end
