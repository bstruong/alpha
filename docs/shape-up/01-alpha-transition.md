# Transition Plan: `berserker` → Project Alpha

**Appetite:** one 2-week small batch to cut Alpha into a shippable evaluation harness core (not a full migration of every historical experiment).  
**Problem:** `berserker` is a capable but sprawling hybrid lab — engine presets, Pi harness, daily Ruby tasks, frontier Flash modules, archived polyglot validation, n8n sidecars — without a single domain language for “run a graded scenario against a local model and publish a comparable score.”  
**Solution:** rename/reshape around five core abstractions, quarantine legacy batteries, and ship one vertical slice: clone sandbox → run agent → grade → emit canonical JSON/MD report.

---

## 1. Audit map (what exists today)

| Keep / promote into Alpha | Role today | Alpha fate |
|---------------------------|------------|------------|
| `engine/` (`models.ini`, `llama-up.sh`, systemd, `workstation.env`) | Local inference lifecycle | **Shared substrate** — Alpha *consumes* endpoints; does not own UX. Document as `Alpha::InferenceTarget` config only. |
| `benchmarks/qwen36-daily/` (`Bench::Task`, library app, graded tasks) | Closest to the target harness | **Seed of Alpha core** — rename module → `Alpha`, generalize beyond one model id. |
| `harness/pi/` | Pi + `pi-llama-cpp` wiring | **Executor adapter** — `Alpha::Runner::PiRpc` (headless). Interactive cockpit moves to Omega. |
| `tests/benchmark_suite/` + `scripts/run_module{1,2,3}_*.py` | Flash telemetry / spec traps / planner-worker | **Battery pack** `scenarios/frontier_*` — keep as optional suites, not the default path. |
| `prompts/` (`prompt-saber`, `prompt-caster`, local agent system prompt) | Task batteries + guardrails | **Scenario fixtures / prompt presets** versioned under Alpha. |
| `CONVENTIONS.md` (`results/` vs `reports/`) | Artifact hygiene | **Law** — Alpha enforces it in the runner. |

| Quarantine / archive (do not block MVP) | Fate |
|-----------------------------------------|------|
| `validation/`, `validation_v2/`, `validation_v3/` | `archive/polyglot-validation/` — historical green-wash lessons only |
| `experiments/` (rate limiter, pii-strip, llama builds, models) | Stay gitignored / out of Alpha path; document pointers |
| `ruby-rails-model-benchmark/`, `llm-benchmark/`, `opencode-agent-eval/` | `archive/` or separate batteries; not required for Circuit 1 |
| `automation/n8n/` | Out of Alpha MVP (Omega or ops later) |
| Root README “Hybrid AI Orchestration” framing | Rewrite to Alpha mission statement |

### Audit steps (week 1, days 1–2)

1. Inventory every entrypoint that starts inference or an agent (`engine/bin/*`, `harness/pi/bin/*`, `benchmarks/qwen36-daily/bin/*`, `scripts/run_*.py`).
2. Tag each: **core** / **battery** / **archive** / **omega-bound**.
3. Freeze new experiment dirs under `experiments/` — Alpha PRs only touch `lib/alpha`, `scenarios/`, `bin/`, `reports/`.
4. Choose canonical language for the runner: **Ruby** (already `Bench`) for Rails-shaped tasks; Python batteries remain callable subprocesses.

---

## 2. Domain model

```
Alpha::Scenario     # named battery member: prompt + sandbox recipe + graders + limits
Alpha::Task         # atomic unit inside a scenario (one instruction, one restore set)
Alpha::Runner       # process supervisor: sandbox prep → executor → collect traces
Alpha::Grader       # deterministic oracle: exit codes, AST, RuboCop diff, hidden tests
Alpha::MetricRecord # one trial's numbers + verdict; append-only
Alpha::Report       # aggregate Pass@k, leaderboard rows, markdown render
Alpha::InferenceTarget  # base_url, model_id, preset, context_window (from engine.ini)
Alpha::Executor         # interface; PiRpc | OpenAIChatCompletions | ShellStub
```

### Mapping from current `Bench`

| Today (`Bench`) | Alpha |
|-----------------|-------|
| `Bench::Task` + `task.yml` | `Alpha::Task` |
| Ordered `ORDER` list + profile | `Alpha::Scenario` (`shipping` / `measurement` profiles preserved) |
| `Bench::Tree.copy` / snapshot / restore | `Alpha::Sandbox` (worktree or copy; see §3) |
| Open3 Pi invocation in `bench.rb` | `Alpha::Runner` + `Alpha::Executor::PiRpc` |
| `verification_test.rb` + restore rules | `Alpha::Grader::Minitest` / `RSpec` / `RuboCopDiff` / `AstDeny` |
| JSON under `results/` | `Alpha::MetricRecord` → `results/<run_id>/` (gitignored) |
| Reading notes under `reports/` | `Alpha::Report` → `reports/<run_id>.md` (tracked when permanent) |

### Suggested Ruby shapes

```ruby
# lib/alpha/task.rb
module Alpha
  class Task
    # name, kind (gate|graded), expected_seed, instruction, invariant,
    # restore[], restore_except[], stable_except[], verifier_path, patches
  end

  class Scenario
    # id, tasks[], profile, inference_target, budget: { wall_s, max_tool_calls, max_tokens }
  end

  class MetricRecord
    # scenario_id, task_name, model_id, prompt_preset,
    # pass: bool, pass_at_1: bool,
    # tool_calls:, prompt_tokens:, completion_tokens:, wall_ms:,
    # grader_results: [{name:, pass:, detail:}],
    # artifact_digest:, seed:, started_at:, finished_at:
  end
end
```

**No-gos for the domain model**

- No ActiveRecord / Postgres inside Alpha MVP (files + JSON only). Persistence of live sessions belongs to Omega.
- No interactive TUI or Turbo UI.
- No “agent improvises the grader.” Graders are checked-in code.

---

## 3. Sandbox & fixture isolation

**Failure mode:** graded tasks mutate a shared library app; prior trial patches and `/tmp` pi scripts leak into the next model’s hints (already learned in Flash / spec-wins work).

### Strategy (pick one primary; second as escape hatch)

**Primary — ephemeral git worktree (Rails library scenarios)**

1. Bare or cached clone of the scenario base app (`library/` today) at a pinned commit SHA.
2. `git worktree add --detach /tmp/alpha/<run_id>/<task> <sha>`.
3. Apply `environment.patch` / buggy overlay from the task dir.
4. Run executor with `cwd` = worktree; `GIT_DIR` isolated.
5. On finish: grade → record digests → `git worktree remove --force`.

**Escape hatch — directory copy** (current `Bench::Tree.copy`)

- Keep for tasks that are not git-friendly; still wipe `tmp/`, `log/`, slot caches between trials.

**Inference isolation**

- Alpha never starts Flash and Tier-1 concurrently on 32GB without an explicit router profile.
- Between trials: erase llama-server slots (`POST /slots/{id}?action=erase`) when the target supports it; never reuse prompt cache across models (`cache_prompt: false`, fixed `seed`).

**Container option (deferred)**

- Docker/podman sandbox is a Circuit 2+ defense if worktrees prove insufficient for network/tool escape. **No-go for MVP.**

---

## 4. Runner pipeline (thin vertical slice)

```
alpha run --scenario qwen36-daily --model qwen36-coder-hybrid --profile shipping
```

1. Resolve `InferenceTarget` (health-check `GET /v1/models`).
2. For each task in scenario order:
   - Provision sandbox
   - Invoke executor with wall clock + tool-call budget
   - Capture: stdout/stderr event log, tool call count, token usage, exit reason
   - Restore protected paths (`restore` / `restore_except`)
   - Run graders
   - Append `MetricRecord` JSON line + per-task folder
3. Render `reports/<run_id>.md` + `results/<run_id>/summary.json`
4. Exit non-zero if any gate task fails (gates short-circuit); graded tasks always recorded

### Executor: Pi headless

```
pi --mode rpc --no-session
```

- `pgroup: true`, kill process group on timeout
- Unbuffered stdout ingestion (non-blocking); same IO discipline Omega will use
- Map model id → Pi `models.json` / `pi-llama-cpp` provider already under `harness/pi`

---

## 5. Graders (deterministic only)

| Grader | Signal | Notes |
|--------|--------|-------|
| `MinitestFile` | `bin/rails test <verification_test.rb>` exit 0 | Current daily path |
| `RSpecSuite` | `bundle exec rspec` exit 0 | Future saber/caster batteries |
| `RuboCopDiff` | offenses introduced vs base | Optional soft fail in measurement profile |
| `AstDeny` | forbid `Float` / `sed` transpile patterns | Spec-trap style |
| `HiddenOracle` | execute hidden probe not in agent prompt | Import from spec-wins lessons |
| `TelemetryBudget` | tool_calls ≤ N, wall_ms ≤ T | Always recorded; fail only if scenario says so |

Shipping profile: invariant text in prompt + visible tests restored after agent run.  
Measurement profile: weaker prompt constraints; grade still hidden/strict.

---

## 6. Output artifacts

### `results/<run_id>/summary.json` (regenerable, gitignored)

```json
{
  "schema": "alpha.report.v1",
  "run_id": "20261012T022600Z-qwen36-hybrid-daily",
  "scenario": "qwen36-daily",
  "model_id": "qwen36-coder-hybrid",
  "prompt_preset": "shipping",
  "inference": { "base_url": "http://127.0.0.1:8080/v1", "preset": "qwen36-coder-hybrid" },
  "aggregate": {
    "pass_at_1": 0.78,
    "tasks_passed": 7,
    "tasks_total": 9,
    "tool_calls_mean": 14.2,
    "wall_ms_total": 421000,
    "prompt_tokens_total": 180000,
    "completion_tokens_total": 22000
  },
  "tasks": [
    {
      "name": "spec-wins",
      "pass": true,
      "pass_at_1": true,
      "tool_calls": 11,
      "prompt_tokens": 24000,
      "completion_tokens": 3100,
      "wall_ms": 48000,
      "graders": [{ "name": "MinitestFile", "pass": true }]
    }
  ]
}
```

### `reports/<run_id>.md` (permanent deliverable when promoted)

- Leaderboard row-ready table: model × scenario × Pass@1 × tool calls × tokens × wall
- Per-task pass/fail with grader detail
- Link to raw `results/` path (not inlined blobs)

---

## 7. Two-week Alpha reshape pitch

### Appetite
2 weeks. Done when `bin/alpha run --scenario qwen36-daily` produces `alpha.report.v1` JSON + markdown for one local model without touching archived experiments.

### Must-haves
- Rename/`Alpha::` extraction from `benchmarks/qwen36-daily`
- Sandbox isolation (worktree or hardened copy) + slot erase
- Pi executor adapter with timeout/process-group kill
- Canonical report schema
- README: Alpha mission only; engine docs remain under `engine/`

### Nice-to-haves (cut first)
- Python frontier modules behind `alpha run --scenario frontier-m2`
- HiddenDecimal oracle
- Multi-model leaderboard HTML

### No-gos
- Building Omega UI inside this repo
- Migrating all `experiments/` and polyglot validation
- Adding Postgres to Alpha
- Supporting cloud inference APIs as first-class targets

### Breadboarding (days 1–3)
Single task `gate-hello` end-to-end through new CLI before migrating the full `ORDER` list.

---

## 8. Refactor sequence

1. Introduce `lib/alpha/` wrapping existing `Bench` without behavior change.
2. Add `bin/alpha` CLI façade.
3. Swap copy → worktree for graded tasks; prove no cross-trial contamination.
4. Emit `alpha.report.v1`; keep old reading reports as adapters.
5. Move `Bench` constants/model hardcodes into scenario YAML.
6. Archive non-core trees behind `archive/` (git mv) in a follow-up PR once CLI is green.
