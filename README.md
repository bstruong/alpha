# Alpha

Headless evaluation & benchmarking harness for self-hosted open-weights LLMs on the **AM5 homelab**.

Formerly the `berserker` lab repo (historical experiments preserved in git history & archive branches). Planning docs: [`docs/shape-up/`](docs/shape-up/). Host roles: [`docs/infrastructure-topology.md`](docs/infrastructure-topology.md).

## Stack (target latest)

| Piece | Version |
|-------|---------|
| Ruby | **4.0.7** (`.ruby-version` / `.mise.toml`) |
| Framework | **Pure Ruby CLI** (Zero runtime gems; Ruby stdlib) |
| Runtime host | AM5 homelab · Fedora Server · RTX 3060 12GB |

## Layout

```
lib/alpha/            # Harness domain — Scenario, Task, Sandbox, Grader, Executor, Runner, Report
bin/alpha             # CLI entrypoint — oracle, run, qualify, doctor, version
scenarios/            # Evaluation scenarios (qwen36-daily, scoped-coding, email-triage, etc.)
engine/               # llama-server presets & lifecycle (AM5 substrate)
harness/pi/           # Pi coding-agent wiring + pi-monitor.rb
prompts/              # Prompt presets / batteries
qualifications/       # Certified Omega model qualification artifacts
docs/                 # Topology + Shape Up
results/              # Regenerable run output (gitignored)
reports/              # Permanent write-ups (tracked when you promote them)
```

## Quick start (AM5 homelab or Haswell desk)

```bash
# Ruby via mise (recommended)
mise install          # reads .mise.toml → ruby 4.0.7
bundle install

bin/alpha help                                                     # CLI commands
bin/alpha doctor                                                   # environment & substrate preflight
bin/alpha oracle --scenario qwen36-daily                           # zero-model self-test of tasks & graders
bin/alpha run --scenario qwen36-daily --model qwen36-coder-hybrid  # run scenario via Pi + llama-server
bin/alpha qualify --run <run_id>                                   # emit omega.qualification.v1
bundle exec rake test                                              # harness unit test suite
```

## What Alpha is / isn’t

- **Is:** deterministic scenario runner + graders + `alpha.report.v1` artifacts that qualify models for Omega.
- **Isn’t:** interactive cockpit (that’s Omega), or a place to keep one-off scratch experiments.
