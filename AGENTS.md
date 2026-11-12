# Alpha — Agent & Harness Conventions

Headless evaluation and benchmarking harness for self-hosted open-weight LLMs (Ruby/Rails coding focus).

## Stack & Commands
- **Runtime:** Pure Ruby 4.0.7 CLI (`mise exec -- ruby ...`, zero runtime gems).
- **Preflight:** `mise exec -- bin/alpha doctor`
- **Zero-model self-test:** `mise exec -- bin/alpha oracle --scenario qwen36-daily` (or `--task <name>`)
- **Unit tests:** `mise exec -- bundle exec rake test`
- **Lint:** `mise exec -- bundle exec rubocop`
- **Watchtower campaigns (graded suites):** submit with `scripts/alpha_watchtower_kick.sh`, then disconnect — the Job owns `jarvis-session` begin/heartbeat/end. Requires [homelab-k3s#41](https://github.com/bstruong/homelab-k3s/pull/41) deployed. Status: `scripts/alpha_watchtower_status.sh` (reads `lease/jarvis-gpu`). Review: `scripts/alpha_watchtower_review.sh`. Optional promote: `scripts/alpha_watchtower_pull.sh`. Local campaign script runs are diagnostic only and are not graded evidence.

## Core Invariants
1. **Deterministic Graders Only:** Never use an LLM to judge whether a task passed. All graders (`lib/alpha/grader/`) must use deterministic exit codes, Minitest/RSpec assertions, AST checks, or JSON schema validation.
2. **Disposable vs. Permanent Output (`CONVENTIONS.md`):**
   - `results/` is strictly for regenerable trial outputs and intermediate traces (gitignored).
   - Local `qualifications/*.json` is gitignored scratch from `bin/alpha qualify`; publish shipping campaigns in [alpha-lab](https://github.com/bstruong/alpha-lab).
3. **Inference Endpoint:**
   - Configure via `OPENAI_BASE_URL` or `LLAMA_SERVER_URL` (OpenAI-compatible HTTP API).
   - Default for local scripts is `http://127.0.0.1:8080`. Never hardcode LAN IPs or private hostnames in tracked code.
4. **Sandbox Isolation:** Sandboxes under `lib/alpha/sandbox.rb` copy the target app without `.git` history so the evaluated agent cannot inspect `solution.patch` or `verification_test.rb`.
