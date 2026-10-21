# Integration Contract: Alpha ↔ Omega

**Problem:** Without a hard handoff, Omega operators will point Pi at unproven local checkpoints (slow Flash left resident, ungraded presets, “feels fine” prompts), while Omega failures stay as unsearchable session scrollback instead of becoming regression fixtures.  
**Solution:** Alpha is the only qualification authority for model+preset pairs Omega may offer as defaults; Omega is the only producer of live-session failure extracts Alpha may ingest as scenarios.

---

## 1. Shared identifiers

| Field | Meaning | Example |
|-------|---------|---------|
| `model_id` | Inference API model / Pi model name | `qwen36-coder-hybrid` |
| `engine_preset` | JARVIS preset id (homelab-k3s `jarvis-models`; local `engine/models.ini` mirror) | `qwen36-coder-hybrid` |
| `prompt_preset` | Guardrail/profile bundle | `shipping` \| `measurement` \| `omega-default` |
| `scenario_id` | Alpha scenario slug | `qwen36-daily` |
| `alpha_run_id` | One Alpha execution | `20261012T022600Z-…` |
| `omega_session_id` | UUID of Omega `Session` | `8f3c…` |
| `repo_fingerprint` | `origin_url` + commit SHA (+ dirty digest) | |

All cross-system JSON uses schema envelopes: `alpha.report.v1`, `alpha.fixture.v1`, `omega.qualification.v1`, `omega.failure_export.v1`.

---

## 2. Handoff A — Alpha qualifies → Omega may deploy

### Rule
Omega’s “Launch” model picker **defaults and “Qualified” badge** only list `(model_id, prompt_preset)` pairs with a current `Omega::AlphaQualification` row. Unqualified pairs are hidden behind an explicit “Unsafe / experimental” disclosure (still allowed for R&D, never the sticky default).

### Qualification workflow

```
Alpha run (scenario gate set) → summary.json
        ↓
alpha qualify --run <run_id> --promote
        ↓
writes qualifications/<model>__<preset>.json  (and optional copy into Omega import path)
        ↓
Omega job: ImportQualifications (watch dir, webhook, or manual rake)
        ↓
AlphaQualification upsert + expire older rows for same key
```

### Gate set for “Qualified” (MVP)

Must pass on pinned scenario `qwen36-daily` (or successor `alpha-core-rails`):

| Requirement | Threshold |
|-------------|-----------|
| All `kind: gate` tasks | Pass@1 = 1.0 |
| Graded task Pass@1 | ≥ 0.70 (configurable per scenario) |
| Mean tool_calls | Recorded; soft budget warn only in MVP |
| Wall clock | Soft budget; hard fail only if scenario declares |
| Report schema | `alpha.report.v1` valid |

Frontier Flash scenarios qualify a **planner** preset separately (`role: planner`) and never auto-default as Omega’s interactive coding runtime.

### `omega.qualification.v1`

```json
{
  "schema": "omega.qualification.v1",
  "model_id": "qwen36-coder-hybrid",
  "engine_preset": "qwen36-coder-hybrid",
  "prompt_preset": "shipping",
  "role": "coder",
  "alpha_run_id": "20261012T022600Z-qwen36-hybrid-daily",
  "scenario_id": "qwen36-daily",
  "pass_at_1": 0.78,
  "report_uri": "file://…/reports/20261012T022600Z-….md",
  "qualified_at": "2026-10-12T02:30:00Z",
  "expires_at": "2026-11-12T02:30:00Z",
  "node_class": "lab-gpu-32g"
}
```

### Omega enforcement points
- `Session` create validates qualification unless `allow_unqualified: true`
- UI shows Alpha Pass@1 + report link on the cockpit status bar
- Expiry: Solid Queue nightly marks expired; defaults fall back to last non-expired coder qualification

### No-gos
- Alpha does not push live config into a running Pi process
- Omega does not re-grade Alpha tasks on launch
- Qualification is not a substitute for Tailscale/auth security

---

## 3. Handoff B — Omega failures → Alpha fixtures

### Rule
Any Omega session with `status: failed` or operator “Promote to Alpha fixture” exports a reproducible `alpha.fixture.v1` package Alpha can turn into a task under `scenarios/omega_regressions/`.

### What gets exported (`omega.failure_export.v1`)

```json
{
  "schema": "omega.failure_export.v1",
  "omega_session_id": "8f3c…",
  "model_id": "qwen36-coder-hybrid",
  "prompt_preset": "omega-default",
  "repo_fingerprint": {
    "url": "git@github.com:bstruong/saber.git",
    "sha": "abc123",
    "dirty": false
  },
  "initial_prompt": "…",
  "follow_ups": ["…"],
  "steers": ["…"],
  "event_log_uri": "…/sessions/8f3c/events.jsonl",
  "artifacts": [
    { "path": "app/models/reminder.rb", "action": "modified", "diff_uri": "…" }
  ],
  "exit_reason": "grader_local_rails_test_failed|timeout|operator_abort|pi_crash",
  "operator_notes": "optional"
}
```

### Alpha ingest recipe

1. `alpha fixture import path/to/export.json`
2. Create task dir:
   - `instruction.md` ← initial prompt (+ annotated follow-ups as separate turns only if scenario kind supports multi-turn; **MVP: single-turn squash** with operator-approved prompt)
   - `buggy/` or patches from artifacts **redacted** (no secrets, no production `.env`)
   - `verification_test.rb` ← operator- or frontier-authored assertion (required before scenario admission)
   - `task.yml` metadata: `origin: omega`, `omega_session_id`, model that failed
3. Human/frontier review gate: fixture cannot join `alpha-core` until a grader exists (prevents “replaying vibes”).

### Privacy / redaction (mandatory)
- Strip API keys, Tailscale IPs optional (keep hostname class only), mail/PII from prompts
- Private repo contents stay on homelab disk; fixture packages are not published publicly
- Alpha CI (if any) runs only on airgapped or private runners

### Failure modes this prevents
- Same Pi steer loop failing nightly without a regression task
- “It worked in chat” without deterministic verify
- Cross-contamination: exports are copied into fresh sandboxes, never reusing Omega’s working tree

---

## 4. Sequence diagrams

### Qualify

```
Operator          Alpha              Filesystem           Omega
   |-- run scenario ->|                  |                  |
   |                  |-- report.v1 ---->|                  |
   |-- qualify ------->|-- qualification ------------------>|
   |                  |                  |<-- import job ---|
   |                  |                  |   upsert Qual    |
   |-- launch session ------------------------------------->|
   |                  |                  |   require Qual   |
```

### Extract

```
Operator          Omega                     Alpha
   |-- session fails ->|                       |
   |-- export fixture ->|-- failure_export.v1 ->|
   |                   |                       |-- fixture import
   |                   |                       |-- (blocked until grader)
   |-- author grader -------------------------------------->|
   |                   |                       |-- admit to scenario
```

---

## 5. Thin slice for Circuit 1 (both systems)

**Week overlap goal:** one qualified coder preset visible in Omega; one deliberate Omega failure imported as a **draft** Alpha task (grader TBD counts as incomplete).

| Day focus | Alpha | Omega |
|-----------|-------|-------|
| 1–3 | `bin/alpha run` + report.v1 on `gate-hello` | Session + fake events + backfill |
| 4–6 | Full `qwen36-daily` through Alpha CLI | Real Pi supervisor + console |
| 7–8 | `alpha qualify` writer | Import qualification + UI badge |
| 9–10 | `fixture import` draft path | `failure_export` from failed session |

---

## 6. Contract tests

- JSON Schemas checked into both repos (or a tiny `sovereign-contracts` submodule later).
- Alpha golden: given a fixture summary, `qualify` emits stable qualification JSON (ignore timestamps).
- Omega: creating a session with unknown `(model_id, prompt_preset)` without `allow_unqualified` returns 422.
- Omega: export of a failed session includes monotonic events with no gaps in `seq`.

---

## 7. Ownership

| Concern | Owner |
|---------|-------|
| Scenario definitions & graders | Alpha repo |
| Process lifecycle & mobile UX | Omega repo |
| `engine/` presets / llama-server | Shared substrate (lives with Alpha/berserker until extracted) |
| Qualification truth | Alpha produces; Omega consumes |
| Failure truth | Omega produces; Alpha consumes after human grader |

Engine binaries and GGUF weights remain on the **AM5 homelab**; neither contract ships weights. The Haswell desk is not an `InferenceTarget`. See [`../infrastructure-topology.md`](../infrastructure-topology.md).
