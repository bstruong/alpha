# Shape Up Pitch: Alpha Gem Foundation & Mechanism/Policy Split

**Codename:** Gem Foundation & Circuit 1 Completion  
**Appetite:** 1 small batch  
**Problem:** Alpha’s core evaluation domain model (`Runner`, `Sandbox`, `Grader`, `Executor`) is decoupled from Rails, but its internal classes still couple to the specific `bstruong/alpha` repository root via `File.expand_path("../../..", __dir__)` calls. This prevents Alpha from being used as a gem across your other homelab repositories (`saber`, `caster`, `omega`) and blocks publishing `alpha-eval` to the Ruby community. Furthermore, two contract items from Circuit 1 remain: `RSpecSuite` / `AstDeny` graders (`01-alpha-transition.md §5`) and Handoff B failure export ingestion (`03-alpha-omega-contract.md §3`).  
**Solution:** Apply the 37signals extraction principle—separate the reusable **Mechanism** (`lib/alpha/`, `bin/alpha`, `alpha.gemspec`) from the private **Policy/Data** (`scenarios/`, `engine/models.ini`, `qualifications/`). Complete Handoff B (`alpha fixture import`) and the remaining deterministic graders.

---

## 1. Mechanism vs. Policy Boundary

| Layer | Responsibility | Packaging |
|---|---|---|
| **Mechanism** (`alpha-eval` gem) | `Alpha::Configuration`, `Runner`, `Sandbox`, `Grader`, `Executor`, `Report`, `MetricRecord` | Bundled in `alpha.gemspec` (`lib/`, `bin/alpha`, `README.md`, `CONVENTIONS.md`). Zero runtime dependencies. |
| **Policy & Fixtures** (Homelab) | `scenarios/` (`qwen36-daily`, etc.), `engine/models.ini`, `qualifications/manifest.json`, `docs/shape-up/` | **Excluded** from `alpha.gemspec`. Stays in the repository as the default workspace when run from `Dir.pwd`. |

---

## 2. Rabbit Holes & Defenses

| Rabbit Hole | Failure Mode | Defense (in scope) |
|---|---|---|
| Private Data Leakage | `gem build` packages homelab IPs, PII test fixtures, or model weights | `spec.files` uses explicit positive allowlist (`lib/**/*.rb`, `bin/alpha`, `README.md`, `CONVENTIONS.md`). Never use `git ls-files` without filtering. |
| Working Directory Confusion | Running `alpha` in an external repo reads gem-internal scenarios | Paths default to `Dir.pwd` (`Alpha.config.root`). In this repo, `Dir.pwd/scenarios` works as before. In external apps, it looks in `./scenarios`. |
| Broken Homelab CLI | Changing path resolution breaks `bin/alpha doctor` or `bin/alpha oracle` | Backward-compatible defaults fallback to local `./engine/models.ini` and `omega.qualification.v1` schema. |
| Unverified Omega Fixtures | Importing failed Omega session without grader poisons benchmark | `FixtureImporter` marks task as `status: draft_needs_grader` and blocks execution until a deterministic test is authored. |

---

## 3. Explicit No-Gos (Protect Appetite)

- No external cloud provider SDK gems (keep pure Ruby standard library; OpenAI-compatible `/v1/chat/completions` covers all standard local/cloud engines).
- No web UI or TUI.
- No database persistence inside Alpha.
- No modifying existing `qwen36-daily` scenario task files.
