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
  not nested inside `results/`). Outside Alpha, `reports/` is not covered by
  root ignore patterns so publication stays structural. **Alpha is the
  exception:** Alpha `reports/` and local qualifications are scratch-only
  (gitignored here); durable campaign evidence is published only in
  [alpha-lab](https://github.com/bstruong/alpha-lab).

A folder named `reports/` was chosen deliberately for non-Alpha projects: it
was never referenced by any existing ignore pattern, so introducing it
required zero new rules and zero risk to already-working projects. Nesting a
`reports/` folder *inside* `results/` was considered and rejected — that
would need a `.gitignore` negation exception per project, which is exactly
the fragile, easy-to-forget pattern that caused the original problem.

### Alpha Project Layout

- **`results/`**: Regenerable trial outputs, intermediate JSON metrics, and ephemeral traces (`results/runs/<run_id>/`). Fully gitignored. Each graded run keeps `run_manifest.json` (created at start, finalized at completion) plus `summary.json` and per-trial `result.json` under this tree. Publish only sanitized bundles to alpha-lab — never commit raw traces here.
- **`reports/`**: Local scratch Markdown from `bin/alpha run` / campaign Jobs. Gitignored. Never the public campaign archive. Re-render deterministically with `bin/alpha render-report --run <id>` from the retained summary + run manifest.
- **`scenarios/`**: Harness-owned evaluation batteries in this repo. Lab-owned scenarios (currently `ikigai-dot`) live only under [alpha-lab](https://github.com/bstruong/alpha-lab) and are reached with `ALPHA_ROOT=/home/brian/Projects/alpha-lab` (or `$ALPHA_LAB_ROOT`).
- **`qualifications/`**: Local `bin/alpha qualify` scratch only (`alpha.qualification.v2`; directory gitignored except `.gitignore` / `.gitkeep`). Alpha must not publish shipping qualifications. Legacy v1 artifacts are obsolete and ignored by the manifest loader.
- **`notes/OPS_TRUST.md`**: Not generated or tracked in Alpha. Active/disabled trust views live in alpha-lab only (Phase 0 disabled; Phase 7 regenerates).

### If you're starting a new benchmark project

Put your harness code and regenerable output under `results/` (gitignored,
as before). Put final write-ups, appendices, and anything else meant to be
read later under a `reports/` folder next to it — unless you are Alpha, in
which case keep reports/qualifications as local scratch and publish durable
evidence in alpha-lab.

**Campaign publication:** sanitized reports and shipping qualification JSON for this lab live only in the public [alpha-lab](https://github.com/bstruong/alpha-lab) repository. Do not commit reports or shipping JSON under Alpha. Graded suites run as Watchtower campaign Jobs only; laptops submit/monitor. `bin/alpha qualify` writes local scratch `alpha.qualification.v2` when a run meets the scenario’s gate / graded Pass@1 thresholds on **scored** shipping-band tasks (use `--promote` to force-write a `qualified: false` record for debugging). Pair measurement runs via `--measurement-run` for ceiling. Campaign driver: `scripts/run_capability_map.sh` (`ALPHA_CAMPAIGN_MODE=full|ops`).
