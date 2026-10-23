# Alpha

Headless evaluation & benchmarking harness for self-hosted open-weights LLMs on the **AM5 homelab**.

Formerly the `berserker` lab repo (historical experiments preserved in git history & archive branches). Planning docs: [`docs/shape-up/`](docs/shape-up/). Host roles: [`docs/infrastructure-topology.md`](docs/infrastructure-topology.md).

## Stack (target latest)

| Piece | Version |
|-------|---------|
| Ruby | **4.0.7** (`.ruby-version` / `.mise.toml`) |
| Rails | **8.1.4** (API mode, SQLite for local learning) |
| Runtime host | AM5 homelab · Fedora Server · RTX 3060 12GB |

## Layout

```
app/                  # Rails API — EvalRun / TaskResult / Qualification mirror
lib/alpha/            # Harness domain — Scenario, Task, Sandbox, Grader, Executor, Runner, Report
bin/alpha             # CLI entrypoint — oracle, run, qualify, version
scenarios/qwen36-daily/   # Seed scenario (former benchmarks/qwen36-daily)
engine/               # llama-server presets (AM5 substrate)
harness/pi/           # Pi coding-agent wiring + pi-monitor.rb
prompts/              # Prompt presets / batteries
docs/                 # Topology + Shape Up
results/              # Regenerable run output (gitignored)
reports/              # Permanent write-ups (tracked when you promote them)
```

## Quick start (AM5 homelab or Haswell desk)

```bash
# Ruby via mise (recommended)
mise install          # reads .mise.toml → ruby 4.0.7
bundle install
bin/rails db:prepare

bin/alpha help                                                     # CLI commands
bin/alpha oracle --scenario qwen36-daily                           # zero-model self-test of tasks & graders
bin/alpha run --scenario qwen36-daily --model qwen36-coder-hybrid  # run scenario via Pi + llama-server
bin/alpha qualify --run <run_id>                                   # emit omega.qualification.v1
bin/rails test                                                     # unit + model tests
bin/rails s                                                        # optional API — GET /up, /eval_runs
```

## What Alpha is / isn’t

- **Is:** deterministic scenario runner + graders + `alpha.report.v1` artifacts that qualify models for Omega.
- **Isn’t:** interactive cockpit (that’s Omega), or a place to keep one-off scratch experiments.
