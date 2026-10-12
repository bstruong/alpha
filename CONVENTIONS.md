# Conventions

## Disposable output vs. permanent deliverables

The root `.gitignore` blanket-ignores `results/` (and `*.log`, `__pycache__/`,
etc.) because most benchmark projects here produce working output that's
genuinely regenerable — raw run logs, scratch check scripts, intermediate
JSON that a harness script can reproduce by running again.

**That rule doesn't distinguish disposable output from permanent
deliverables** — final reports, appendices, anything meant to be read later
rather than regenerated. If a project's actual findings end up inside a
folder literally named `results/`, they get silently excluded from `git
add`/`git status` and only survive if someone remembers to force-add them.
This already happened once: `ruby-rails-model-benchmark`'s three rounds of
reports, appendices, and raw model-output JSON all lived under `results/`
and were only rescued from that near-miss by a manual `git add -f` caught
during review before the archive commit — not by anything structural.

### The rule going forward

- **Disposable/regenerable working output** — harness source code, run logs,
  scratch/check scripts, anything a script could reproduce by running again —
  stays in `results/` (or an equivalent per-project name, e.g.
  `ab-results/`) and stays covered by the blanket ignore rules above.
- **Permanent deliverables** — final reports, appendices, anything a reader
  would open later rather than a script regenerating — live in a sibling
  **`reports/`** folder instead, at the project's top level (`<project>/reports/`,
  not nested inside `results/`). `reports/` is never covered by any pattern
  in the root `.gitignore`, so nothing needs a per-project exception to keep
  it tracked — the safety is structural, not something to remember.

A folder named `reports/` was chosen deliberately: it was never referenced
by any existing ignore pattern, so introducing it required zero new rules
and zero risk to already-working projects. Nesting a `reports/` folder
*inside* `results/` was considered and rejected — that would need a
`.gitignore` negation exception per project, which is exactly the
fragile, easy-to-forget pattern that caused the original problem.

### Per-project status (as of 2026-08-08)

| Project | Has a `results/`-named folder? | Deliverables location | Status |
|---|---|---|---|
| `llm-benchmark/` | No — `bin/benchmark` only prints to stdout | `BENCHMARK.md` at project top level | Already safe, no `reports/` needed |
| `opencode-agent-eval/` | No — uses `ab-results/`, `results_32b_patched/`, `results_qwen3_32b/` (none match the exact-name `results/` rule) | `README.md`, tracked `.diff`/`.txt` files | Already safe by naming, no `reports/` needed today — if a folder literally named `results/` is ever added here, revisit |
| `prompts/` | N/A — static template files only | N/A | Not applicable |
| `archive/benchmarks-legacy/ruby-rails-model-benchmark/` | Yes (under archive) | `reports/round{1,2,3}/` | Archived with berserker → Alpha cleanup |
| Alpha (repo root) | `results/` gitignored | `reports/` for promoted run write-ups | Active |

### If you're starting a new benchmark project

Put your harness code and regenerable output under `results/` (gitignored,
as before). Put final write-ups, appendices, and anything else meant to be
read later under a `reports/` folder next to it. Nothing else to configure.
