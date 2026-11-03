# Alpha

Headless evaluation and benchmarking harness for self-hosted open-weight LLMs, with a focus on **Ruby and Rails coding tasks**.

Alpha runs deterministic scenarios against a local (or remote) OpenAI-compatible inference endpoint, grades results without LLM judges, and emits qualification artifacts that downstream tools (such as [Omega](https://github.com/bstruong/omega)) can consume.

## Stack

| Piece | Version |
|-------|---------|
| Ruby | **4.0.7** (`.ruby-version` / `.mise.toml`) |
| Framework | Pure Ruby CLI (stdlib only at runtime) |
| Inference | Any OpenAI-compatible HTTP API (e.g. llama-server) |

## Layout

```
lib/alpha/            # Harness domain — Scenario, Task, Sandbox, Grader, Executor, Runner, Report
bin/alpha             # CLI — oracle, run, qualify, doctor, version
scenarios/            # Evaluation scenarios (scoped-coding, email-triage, etc.)
engine/               # llama-server presets and lifecycle helpers
harness/pi/           # Pi coding-agent wiring
prompts/              # Prompt presets
qualifications/       # Published qualification artifacts
docs/                 # Design notes and Shape Up pitches
results/              # Regenerable run output (gitignored)
reports/              # Permanent write-ups (tracked when promoted)
```

## Quick start

```bash
# Ruby via mise (recommended)
mise install          # reads .mise.toml → ruby 4.0.7
bundle install

# Point at an OpenAI-compatible endpoint (llama-server, vLLM, etc.)
export OPENAI_BASE_URL="http://127.0.0.1:8080/v1"

bin/alpha help
bin/alpha doctor
bin/alpha oracle --scenario qwen36-daily              # zero-model self-test of tasks & graders
bin/alpha run --scenario qwen36-daily --model <name>  # run via Pi + inference endpoint
bin/alpha qualify --run <run_id>                      # emit omega.qualification.v1
bundle exec rake test
```

## Configuration

| Variable | Purpose |
|----------|---------|
| `OPENAI_BASE_URL` | Chat completions base (preferred), e.g. `http://127.0.0.1:8080/v1` |
| `LLAMA_SERVER_URL` | Alternate base URL if `OPENAI_BASE_URL` is unset |
| `BENCHMARK_MODEL` / `BENCH_MODEL` | Default model id for profiling scripts |

Defaults assume a local llama-server on `127.0.0.1:8080`. Do not commit machine-specific hosts or secrets; use env vars or a gitignored `.env`.

## What Alpha is / isn’t

- **Is:** a deterministic scenario runner + graders + `alpha.report.v1` / qualification artifacts.
- **Isn’t:** an interactive agent cockpit (see Omega), or a place for one-off scratch experiments.

## Documentation

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — tests, conventions, PRs
- [`SECURITY.md`](SECURITY.md) — reporting vulnerabilities
- [`docs/`](docs/) — topology notes and Shape Up pitches
- [`AGENTS.md`](AGENTS.md) — harness invariants for automated agents
- [`CONVENTIONS.md`](CONVENTIONS.md) — disposable vs permanent output

## License

[MIT](LICENSE)
