# Contributing

Thanks for interest in Alpha. Small, focused changes with tests are easiest to review.

## Setup

```bash
mise install
bundle install
export OPENAI_BASE_URL="http://127.0.0.1:8080/v1"   # optional for oracle / unit tests
```

## Tests and checks

```bash
bundle exec rake test
bin/alpha oracle --scenario qwen36-daily   # grader/task self-test (no model required for oracle)
bundle exec rubocop                        # if configured in your environment
```

## Guidelines

- Keep graders **deterministic** — no LLM-as-judge in `lib/alpha/grader/`.
- Put regenerable output under `results/` (gitignored). Promote lasting write-ups to `reports/` or `qualifications/`.
- Do not commit secrets, API keys, personal emails, LAN IPs, or private hostnames. Use environment variables.
- Prefer env-based inference URLs over hardcoding hosts in Ruby/Python helpers.
- Follow [`CONVENTIONS.md`](CONVENTIONS.md) and [`AGENTS.md`](AGENTS.md).

## Pull requests

1. Describe the problem and the approach.
2. Note how you tested (commands above).
3. Keep diffs scoped; avoid unrelated formatting churn.
