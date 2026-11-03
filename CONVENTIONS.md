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

### Alpha Project Layout

- **`results/`**: Regenerable trial outputs, intermediate JSON metrics, and ephemeral traces (`results/runs/<run_id>/`). Fully gitignored.
- **`reports/`**: Promoted permanent benchmark reports, leaderboards, and qualification summaries. Tracked in git.
- **`scenarios/`**: Standardized evaluation batteries (`qwen36-daily`, `scoped-coding`, `pii-scrubbing`, `ocr-extraction`, `email-triage`).
- **`qualifications/`**: Formal JSON qualification artifacts (`alpha.qualification.v1`). Tracked in git.

### If you're starting a new benchmark project

Put your harness code and regenerable output under `results/` (gitignored,
as before). Put final write-ups, appendices, and anything else meant to be
read later under a `reports/` folder next to it. Nothing else to configure.

Published campaign reports and shipping qualification snapshots for this lab live in the public [alpha-lab](https://github.com/bstruong/alpha-lab) repository. Do not commit personal shipping JSON under `qualifications/` in this repo.
