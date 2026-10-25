# Alpha — Agent & Harness Conventions

Headless evaluation & benchmarking harness for self-hosted open-weights LLMs on **Watchtower** (AM5 homelab).

## Stack & Commands
- **Runtime:** Pure Ruby 4.0.7 CLI (`mise exec -- ruby ...`, zero runtime gems).
- **Preflight & Health Check:** `mise exec -- bin/alpha doctor`
- **Zero-Model Task/Grader Self-Test:** `mise exec -- bin/alpha oracle --scenario qwen36-daily` (or `--task <name>`)
- **Unit Test Suite:** `mise exec -- bundle exec rake test`
- **Lint:** `mise exec -- bundle exec rubocop`

## Core Invariants
1. **Deterministic Graders Only:** Never use an LLM to judge whether a task passed. All graders (`lib/alpha/grader/`) must use deterministic exit codes, Minitest/RSpec assertions, AST checks, or JSON schema validation.
2. **Disposable vs. Permanent Output (`CONVENTIONS.md`):**
   - `results/` is strictly for regenerable trial outputs and intermediate traces (gitignored).
   - `reports/` and `qualifications/` are permanent, git-tracked deliverables.
3. **JARVIS Inference Endpoint:**
   - LAN / Operator access uses `http://ai.example.local/v1` (or `http://127.0.0.1:8080/v1` when running directly on Watchtower).
   - Never hardcode `127.0.0.1:8080` (`hostPort` 8080 is bound to `127.0.0.1` only).
4. **Sandbox Isolation:** Sandboxes under `lib/alpha/sandbox.rb` copy the target app without `.git` history so the evaluated agent cannot inspect `solution.patch` or `verification_test.rb`.
