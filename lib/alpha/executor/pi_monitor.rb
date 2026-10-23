#!/usr/bin/env ruby
# frozen_string_literal: true

# Sidecar log and heartbeat filter for the Pi coding agent.
# Raw stdout and stderr go to the log. The terminal only sees tool actions.

require "fileutils"
require "json"
require "open3"
require "shellwords"

SCRIPT_DIR = __dir__
HARNESS_DIR = File.expand_path("..", SCRIPT_DIR)
ENV["PI_CODING_AGENT_DIR"] ||= HARNESS_DIR
SESSIONS_DIR = File.join(HARNESS_DIR, "sessions")
DEFAULT_LOG = File.join(SESSIONS_DIR, "current_run.log")
DEFAULT_PI = File.join(HARNESS_DIR, "node_modules", ".bin", "pi")

MODEL_TAG = ENV.fetch("PI_MODEL_TAG", "Qwen-35B")
HEARTBEAT_PREFIX = "[#{MODEL_TAG}] 🛠️ Executing:"
ANSI = /\x1b(?:[@-Z\\-_]|\[[0-?]*[ -\/]*[@-~])/
ENGLISH_STOPS = %w[
  the a an through out how where what why all each every more this that these
  those to some any carefully now again code below it we i let first next then
].freeze

def false_positive?(tool, rest)
  words = rest.strip.split
  return true if words.empty?
  return true if ENGLISH_STOPS.include?(words[0].downcase)

  tool.match?(/\A(?:read|write|edit)\z/) && words.size > 1 &&
    !rest.start_with?("\"", "'") &&
    !(words[0].include?(":") || words[1].start_with?(":"))
end

def heartbeat(text)
  "#{HEARTBEAT_PREFIX} #{text}"
end

def from_json(obj)
  return nil unless obj.is_a?(Hash)

  if obj["type"] == "toolCall" || obj.key?("arguments") || obj.key?("command")
    name = (obj["name"] || obj["tool"] || obj["toolName"] || "bash").to_s
    args = obj["arguments"] || {}
    args = JSON.parse(args) if args.is_a?(String) rescue args
    if args.is_a?(Hash)
      return heartbeat(args["command"]) if args["command"]
      return heartbeat("#{name} #{args["path"]}") if args["path"]
      return heartbeat("#{name} #{args["file_path"]}") if args["file_path"]
    end
    return heartbeat(obj["command"]) if obj["command"]

    return heartbeat(name)
  end

  if obj["type"] == "message_update"
    event = obj["assistantMessageEvent"] || {}
    if event["type"] == "toolcall_start"
      return heartbeat(event["toolName"] || event["name"] || "tool")
    end
  end

  if obj["type"] == "message"
    Array(obj.dig("message", "content")).each do |part|
      next unless part.is_a?(Hash) && part["type"] == "toolCall"

      args = part["arguments"] || {}
      name = part["name"] || "tool"
      return heartbeat(args["command"]) if args.is_a?(Hash) && args["command"]
      return heartbeat("#{name} #{args["path"]}") if args.is_a?(Hash) && args["path"]

      return heartbeat(name)
    end
  end
  nil
end

def extract_action(line)
  text = line.strip
  return nil if text.empty?
  return text if text.start_with?(HEARTBEAT_PREFIX)

  if (match = text.match(/^(?:\[.*?\]\s*)?(?:Executing|Running|Run):\s*(.+)$/i))
    return heartbeat(match[1].strip)
  end

  if text.include?("{") && text.match?(/name|toolCall|command|toolName/)
    start = text.index("{")
    finish = text.rindex("}")
    if start && finish && finish > start
      action = from_json(JSON.parse(text[start..finish])) rescue nil
      return action if action
    end
  end

  if (match = text.match(/(?:toolCall|tool_call|Tool Call|tool):\s*(\w+)\s*(\{.*\})?/i))
    tool = match[1]
    raw = match[2]
    if raw
      cmd = raw[/'command'\s*:\s*'([^']+)'|"command"\s*:\s*"([^"]+)"/, 1] ||
        raw[/'command'\s*:\s*'([^']+)'/, 1]
      return heartbeat(cmd) if cmd
      path = raw[/'path'\s*:\s*'([^']+)'|"path"\s*:\s*"([^"]+)"/, 1]
      return heartbeat("#{tool} #{path}") if path

      return heartbeat("#{tool} #{raw}")
    end
    return heartbeat(tool)
  end

  if (match = text.match(/<tool_call>(.*?)<\/tool_call>/i))
    inner = match[1].strip
    parsed = JSON.parse(inner) rescue nil
    if parsed.is_a?(Hash)
      args = parsed["arguments"]
      return heartbeat(args["command"]) if args.is_a?(Hash) && args["command"]

      return heartbeat(parsed["name"] || "tool")
    end
    return heartbeat(inner)
  end

  return heartbeat(text.sub(/^\$\s+/, "")) if text.start_with?("$ ")
  return heartbeat($1.strip) if text =~ /^bash[:\s]+(.+)$/i

  [
    [ /^(?:Writing|Write)(?:\s+to|\s+file)?(?::|\s)\s*(.+)$/i, "write" ],
    [ /^(?:Editing|Edit)(?:\s+file)?(?::|\s)\s*(.+)$/i, "edit" ],
    [ /^(?:Reading|Read)(?:\s+file)?(?::|\s)\s*(.+)$/i, "read" ]
  ].each do |pattern, tool|
    next unless (match = text.match(pattern))
    path = match[1].strip
    return heartbeat("#{tool} #{path}") unless false_positive?(tool, path)
  end

  if (match = text.match(/^(bash|read|write|edit|grep|find|ls)\s+(.+)$/i))
    tool = match[1].downcase
    rest = match[2].strip
    return nil if false_positive?(tool, rest)

    return heartbeat(tool == "bash" ? rest : "#{tool} #{rest}")
  end

  return heartbeat($1.strip) if text =~ /^Action:\s*(.+)$/i && !$1.downcase.start_with?("action input")
  return heartbeat($1.strip) if text =~ /^Action Input:\s*(.+)$/i

  nil
end

def monitor(cmd, log_path, telemetry_path: nil, passthrough: false, max_tool_calls: nil)
  FileUtils.mkdir_p(File.dirname(log_path))
  last = nil
  buffer = +""
  in_block = false
  tool_calls = 0
  prompt_tokens = 0
  completion_tokens = 0
  tool_budget_exceeded = false

  Open3.popen2e(*cmd) do |stdin, out, wait|
    # Pi reads piped stdin to EOF before the first model call. Leaving this
    # open deadlocks: the agent waits for stdin, and we wait for its stdout.
    stdin.close
    File.open(log_path, "w") do |log|
      out.each_line do |raw|
        log.write(raw)
        log.flush
        if passthrough
          $stdout.write(raw)
          next
        end

        clean = raw.gsub(ANSI, "").strip
        next if clean.empty?

        parsed = JSON.parse(clean) rescue nil
        if parsed.is_a?(Hash)
          # 1. Extract token usage from Pi JSON event stream
          if parsed["type"] == "message_end" || parsed["type"] == "turn_end"
            usage = parsed.dig("message", "usage") || parsed["usage"]
            if usage.is_a?(Hash)
              inp = (usage["input"] || usage["prompt_tokens"] || usage["promptTokens"]).to_i
              out = (usage["output"] || usage["completion_tokens"] || usage["completionTokens"]).to_i
              prompt_tokens += inp
              completion_tokens += out
            end
          elsif parsed["type"] == "agent_end"
            messages = Array(parsed["messages"])
            asst_usages = messages.select { |m| m["role"] == "assistant" }.map { |m| m["usage"] }.compact
            if asst_usages.any?
              total_inp = asst_usages.sum { |u| (u["input"] || u["prompt_tokens"] || u["promptTokens"]).to_i }
              total_out = asst_usages.sum { |u| (u["output"] || u["completion_tokens"] || u["completionTokens"]).to_i }
              prompt_tokens = [prompt_tokens, total_inp].max
              completion_tokens = [completion_tokens, total_out].max
            end
          end

          # 2. Tool call heartbeat and count
          action = from_json(parsed)
          if action && action != last
            tool_calls += 1
            puts action
            $stdout.flush
            last = action

            if max_tool_calls && tool_calls >= max_tool_calls
              warn "[Pi Monitor] Tool call budget reached (#{tool_calls}/#{max_tool_calls}). Terminating process."
              tool_budget_exceeded = true
              begin
                Process.kill("TERM", wait.pid) rescue nil
              rescue StandardError
              end
              break
            end
          end
          next
        end

        if (tok_match = clean.match(/(?:prompt_tokens|promptTokens)["']?\s*:\s*(\d+)/i))
          prompt_tokens += tok_match[1].to_i
        end
        if (tok_match = clean.match(/(?:completion_tokens|completionTokens)["']?\s*:\s*(\d+)/i))
          completion_tokens += tok_match[1].to_i
        end

        if clean.include?("<tool_call>")
          in_block = true
          buffer = clean
          unless clean.include?("</tool_call>")
            next
          end
          in_block = false
        elsif in_block
          buffer << clean
          next unless clean.include?("</tool_call>")

          in_block = false
          clean = buffer
        end

        action = extract_action(in_block ? buffer : clean)
        next unless action && action != last

        tool_calls += 1
        puts action
        $stdout.flush
        last = action

        if max_tool_calls && tool_calls >= max_tool_calls
          warn "[Pi Monitor] Tool call budget reached (#{tool_calls}/#{max_tool_calls}). Terminating process."
          tool_budget_exceeded = true
          begin
            Process.kill("TERM", wait.pid) rescue nil
          rescue StandardError
          end
          break
        end
      end
    end

    if tool_budget_exceeded
      begin
        Process.kill("TERM", wait.pid) rescue nil
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        while wait.alive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          sleep 0.1
        end
        Process.kill("KILL", wait.pid) if wait.alive? rescue nil
      rescue StandardError
      end
    end

    exit_status = wait.value.exitstatus || 1

    if telemetry_path
      FileUtils.mkdir_p(File.dirname(telemetry_path))
      File.write(telemetry_path, JSON.pretty_generate({
        "tool_calls" => tool_calls,
        "prompt_tokens" => prompt_tokens,
        "completion_tokens" => completion_tokens,
        "tool_budget_exceeded" => tool_budget_exceeded
      }))
    end

    exit_status
  end
end

def dummy(log_path)
  puts "--- [Pi Monitor] Starting Dummy Verification Run ---"
  puts "--- Log destination: #{log_path} ---"
  script = <<~'RUBY'
    def emit(line) = puts(line)
    emit "[Pi Agent] Initializing v1.0.3..."
    emit "Connecting to http://127.0.0.1:8080/v1 (Local llama.cpp)..."
    emit "<think>"
    emit "Reviewing specs/ARCH_PLAN_V3.md to understand requirements."
    emit "</think>"
    emit "toolCall: read {'path': 'specs/ARCH_PLAN_V3.md'}"
    emit "write validation_v3/pii_scrubber.rb"
    emit "Executing: ruby validation_v3/test_scrubber.rb"
    emit "$ rubocop -A validation_v3/pii_scrubber.rb"
    emit "Done with Phase 1 execution."
  RUBY
  status = monitor([ RbConfig.ruby, "-e", script ], log_path)
  return status unless status.zero?

  body = File.read(log_path)
  ok = body.include?("<think>") && body.include?("ruby validation_v3/test_scrubber.rb") && body.include?("rubocop -A")
  unless ok
    warn "[FAIL] Log did not contain expected content"
    return 1
  end

  puts "--- [Pi Monitor] Verification Succeeded: All reasoning captured in sidecar log; heartbeat intercepted cleanly! ---"
  0
end

def main(argv)
  log_path = ENV.fetch("PI_LOG_FILE", DEFAULT_LOG)
  telemetry_path = ENV["PI_TELEMETRY_FILE"]
  pi_bin = ENV.fetch("PI_BIN", DEFAULT_PI)
  custom = ENV["PI_MONITOR_CMD"]
  max_tool_calls = ENV["PI_MAX_TOOL_CALLS"] ? ENV["PI_MAX_TOOL_CALLS"].to_i : nil
  dummy_mode = false
  forwarded = []
  index = 0
  while index < argv.length
    arg = argv[index]
    case arg
    when "--dummy"
      dummy_mode = true
      index += 1
    when "--log-file"
      log_path = argv.fetch(index + 1)
      index += 2
    when "--telemetry-file"
      telemetry_path = argv.fetch(index + 1)
      index += 2
    when "--max-tool-calls"
      max_tool_calls = argv.fetch(index + 1).to_i
      index += 2
    when "--pi-bin"
      pi_bin = argv.fetch(index + 1)
      index += 2
    when "--cmd"
      custom = argv.fetch(index + 1)
      index += 2
    when "--"
      forwarded.concat(argv[(index + 1)..] || [])
      break
    else
      forwarded << arg
      index += 1
    end
  end

  return exit(dummy(log_path)) if dummy_mode

  cmd = if custom
    Shellwords.split(custom) + forwarded
  else
    abort "Error: Pi binary not found at #{pi_bin}" unless File.exist?(pi_bin)

    [ pi_bin, *forwarded ]
  end
  info = forwarded.intersect?(%w[--help -h --version -v --list-models])
  exit monitor(cmd, log_path, telemetry_path: telemetry_path, passthrough: info, max_tool_calls: max_tool_calls)
end

main(ARGV)
