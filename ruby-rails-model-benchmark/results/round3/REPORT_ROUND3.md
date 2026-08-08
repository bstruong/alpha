# Direct Ruby/Rails Model Benchmark — Round 3 (qwen3:8b)

**Date:** 2026-08-08
**Model:** `qwen3:8b` (5.2 GB), run in default/non-thinking mode via Ollama's `think: false` API parameter — confirmed via log inspection that all 90 generations show `thinking_present=False`, so mode was consistent throughout.
**Sandbox:** `/home/user/benchmarks/rails-scratch` — same disposable sandbox as Rounds 1/2, confirmed clean at Round 2's final commit (`2544dee`) before starting, no drift.
**Scope:** the exact same 30 prompts from Rounds 1 and 2, reused verbatim from their `prompts.json` source files (not re-transcribed from prose, so wording is byte-identical) × 1 model × 3 fresh runs = 90 generations.
**Raw data:** `APPENDIX_ROUND3.md` (all 90 outputs, annotated with scores) and `scores_a.json` / `scores_b.json` / `scores_d.json` / `scores_e.json` / `scores_f.json` / `scores_g.json` / `scores_h.json`.

## ⚠️ Read this before the tables: this is NOT the same measurement as the earlier OpenCode-based qwen3:8b evaluation

A separate, earlier evaluation ran qwen3:8b through **OpenCode's agentic tool-calling/diff-apply layer** and scored it on **clean-apply rate and corruption defects** — i.e., whether the *tool* correctly wrote the model's proposed edit to disk without corrupting it. That is a measurement of the tool-calling/diff-apply pipeline's reliability, not of the model's code-generation quality.

**This round measures something different: raw prompt-in/code-out generation quality, with no tool-calling, no diff-apply, no agentic harness at all** — identical in kind to what Rounds 1 and 2 measured for the other three models. The two numbers are not comparable and this report does not attempt to reconcile them. If you recall a ~50% clean-apply figure from that earlier OpenCode evaluation, **nothing below confirms, contradicts, or updates that number** — it's a different instrument measuring a different failure surface. Do not average, compare, or substitute one for the other.

## The two-axis confound (stated, not resolved)

qwen3:8b differs from the three Round 1/2 models on two independent axes simultaneously: (a) it's a general-purpose model, not a code-specialized one like the qwen2.5-coder/deepseek-coder lines, and (b) its estimated knowledge cutoff (~late 2024, unofficial) is meaningfully later than the ~Nov 2023–June 2024 range of the Round 1/2 models. Any difference in the results below could stem from either factor, or both, or neither (ordinary run-to-run variance) — this round's design cannot cleanly attribute a given result to "general-purpose vs. code-specialized" or to "later cutoff." Where a difference is notable, it's flagged as a difference, not attributed to a specific cause.

---

## Category A — Generic Ruby (/12 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 9/12 | 6/12 |
| qwen2.5-coder:14b | 12/12 | 9/12 |
| deepseek-coder-v2-lite:16b | 12/12 | 9/12 |
| **qwen3:8b** | **12/12** | **9/12** |

By prompt — "executes/behavior," both out of 3:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | **qwen3:8b** |
|---|---|---|---|---|
| A1 word_frequency | 1/3 · 1/3 | 3/3 · 3/3 | 3/3 · 0/3 | **3/3 · 3/3** |
| A2 Stack class | 2/3 · 2/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| A3 safe_divide | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| A4 extract_emails | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 0/3** |

qwen3:8b is the **only model across all three rounds to avoid the A3 `safe_divide` Float-coercion trap** that caught both qwen2.5-coder models in Round 1 — but it's also the **only model to fail A4 (`extract_emails`)**, which every Round 1 model passed 9/9. Root cause verified: its regex character class for the email local-part, `[\w\.-]+`, omits `+`, truncating `dev.team+alerts@sub.example.io` mid-match — a genuine, reproducible regex bug, not a harness artifact (confirmed identical failure shape across all 3 runs).

---

## Category B — Rails 7.1-era idioms (/15 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 14/15 | 11/15 |
| qwen2.5-coder:14b | 15/15 | 12/15 |
| deepseek-coder-v2-lite:16b | 15/15 | 12/15 |
| **qwen3:8b** | **14/15** | **10/15** |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | **qwen3:8b** |
|---|---|---|---|---|
| B1 migration | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| B2 User validations | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 2/3** |
| B3 PostsController#publish | 2/3 · 2/3 | 3/3 · 3/3 | 3/3 · 3/3 | **2/3 · 2/3** |
| B4 Order enum + validate:true + scope | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 0/3 | **3/3 · 0/3** |
| B5 admin/articles routes | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |

**B4 fails 3/3 for qwen3:8b too — the exact same `enum status: {...}, validate: true` pre-Rails-7.0 calling-convention error found in every Round 1/2 model.** This is now confirmed across a *fourth* model, spanning both code-specialized and general-purpose lines and both cutoff eras — the strongest evidence yet that this specific syntax pattern is broadly under-represented in training data generally, not tied to any one model family or era.

B3's one failing run (verified against raw output) is a new, distinct miss: the controller sets `flash[:notice]` and correctly updates status/`published_at`, but never calls `redirect_to` or `render` at all — Rails' implicit 204-no-content fallback kicks in silently, so the flash message is set but never actually displayed to a user. A genuinely different mistake from any B3 failure seen in Rounds 1/2.

---

## Category C — Rails-8-boundary knowledge check (qualitative, /9 runs, not scored into correctness)

All 9 runs (C1/C2/C3 × 3) landed uniformly on Rails-7-era answers — Sidekiq+ActiveJob for background jobs, Devise for authentication, Sprockets manifest.js for the asset pipeline — with **zero hedging and zero Rails-8-specific content** (no mention of Solid Queue, the built-in `rails generate authentication` generator, or Propshaft) in any run.

### Prediction check: "partial/inconsistent Rails-8 awareness" — **refuted**

The brief predicted this model's later (~late 2024) cutoff sitting close to Rails 8.0 (Nov 2024) would produce partial or inconsistent Rails-8 awareness, unlike the clean "impossible to know" case for the Round 1/2 models. That did not happen: qwen3:8b was exactly as confidently and uniformly Rails-7-locked in its answers as all three Round 1/2 models, with no detectable difference in framing, hedging, or content. Whatever this model's actual cutoff is, it did not surface here — worth noting given the two-axis confound above, since "general-purpose model less exposed to bleeding-edge Rails 8 discourse than a code-specialized model with a similar cutoff" is at least as plausible an explanation as "cutoff isn't actually as late as estimated."

---

## Category D — Rails 7.2 boundary (/12 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 12/12 | 8/12 |
| qwen2.5-coder:14b | 12/12 | 11/12 |
| deepseek-coder-v2-lite:16b | 12/12 | 11/12 |
| **qwen3:8b** | **12/12** | **9/12** |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | **qwen3:8b** |
|---|---|---|---|---|
| D1 transaction-safe job enqueue | 3/3 · 1/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| D2 YJIT config | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| D3 Ruby-version-floor initializer | 3/3 · 2/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 0/3** |
| D4 after_commit/after_rollback | 3/3 · 2/3 | 3/3 · 2/3 | 3/3 · 2/3 | **3/3 · 3/3** |

### Prediction check: "cleaner passes on Category D" — **holds for D1/D4, does not for D3**

D1 (behaviorally correct 3/3, matching the two best Round 1/2 models) and D4 (3/3, the *only* clean sweep across all four models on this prompt) support the prediction that this fine-grained 7.2 boundary sits comfortably inside qwen3:8b's window. **D3 is the exception and needs a caveat**: all 3 runs fail, but this repeats a known harness limitation from Round 2 — D3's check runs generated initializer code via plain `ruby`, not a booted Rails app, so any reference to the `Rails` constant fails regardless of the code's actual merit. On inspection, though, qwen3:8b's D3 code has a genuine defect independent of that limitation: it compares `RUBY_VERSION` (a string) against `Rails.version.split('.').first.to_f` (a float derived from the *Rails* version, not a stated Ruby minimum) — a type-mismatched, semantically confused comparison that would fail even inside a real Rails boot. So D3 remains inconclusive on the *harness's* terms but shows a real, inspectable code quality issue on manual review.

---

## Category E — Gem-referencing tasks (/9 runs per model)

| Model | Executes | Behaviorally correct | Hallucinated API calls |
|---|---|---|---|
| qwen2.5-coder:7b | 9/9 | 6/9 | 0 |
| qwen2.5-coder:14b | 9/9 | 5/9 | 1 |
| deepseek-coder-v2-lite:16b | 9/9 | 6/9 | 0 |
| **qwen3:8b** | **9/9** | **6/9** | **2** |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | **qwen3:8b** |
|---|---|---|---|---|
| E1 Kaminari pagination | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| E2 ActiveStorage `has_one_attached` | 3/3 · 3/3 | 3/3 · 2/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| E3 ransack fuzzy search | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 0/3 | **3/3 · 0/3** |

**E3 fails 3/3 again, but with qwen3:8b's own distinct hallucinations, plus one genuine positive finding no Round 1/2 model showed:**
- Run 1: `include Ransack::Search` — `Ransack::Search` is a real class in the gem (used internally as `Ransack::Search.new(...)`), but it is not a module meant to be mixed in. `include`-ing a Class raises exactly the `TypeError: wrong argument type Class (expected Module)` observed.
- Run 3: `include Ransack::Scoping` — this constant does not exist anywhere in the ransack gem; a genuine hallucination. **But the same run correctly defines `ransackable_attributes`/`ransackable_associations`** — the Ransack 4.x mandatory security allowlist that all three Round 1/2 models universally failed to know about. This is the first and only appearance of that correct detail across 270 total generations touching this gem. The run still fails overall, but for an unrelated reason (the hallucinated `Ransack::Scoping` include), not because it repeated Round 1/2's universal miss.

E1/E2 are clean across the board — pagination and ActiveStorage attachment usage are correct in every run, no hallucinations on the "well-known, central" gem APIs (matches the pattern from Rounds 1/2 that hallucinations concentrate on less-central method surfaces, not everyday usage).

---

## Category F — Convention-heavy Rails patterns (/15 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 15/15 | 12/15 |
| qwen2.5-coder:14b | 15/15 | 10/15 |
| deepseek-coder-v2-lite:16b | 15/15 | 14/15 |
| **qwen3:8b** | **15/15** | **12/15** |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | **qwen3:8b** |
|---|---|---|---|---|
| F1 has_many :through | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| F2 polymorphic association | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| F3 callback timing (shipped_at) | 3/3 · 2/3 | 3/3 · 1/3 | 3/3 · 2/3 | **3/3 · 0/3** |
| F4 Concern extraction | 3/3 · 1/3 | 3/3 · 0/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| F5 strong params | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |

**F3 is qwen3:8b's worst single result (0/3) and it's a clean, classic Rails bug, reproduced identically in all 3 runs:** an `after_save :set_shipped_at_if_shipped` callback correctly checks `status == 'shipped'` and sets `self.shipped_at = Time.current` — but never calls `save`/`update_column` again, so the assignment lives only in memory and is silently discarded. Right hook, right guard condition, missing persistence step — a subtler and more specific mistake than the vaguer misses seen from the other models on this same prompt in Round 2.

F1/F2/F5 are clean sweeps for every model in the study, all four — the highest-agreement prompts in the entire three-round benchmark.

---

## Category G — Test-writing (2 prompts × 3 runs = 6 runs)

| Model | Well-formed | Passes vs. correct | Passes vs. broken | **False positive** |
|---|---|---|---|---|
| qwen2.5-coder:7b | 6/6 | 0/6 | 0/6 | 0/6 |
| qwen2.5-coder:14b | 5/6 | 1/6 | 0/6 | 0/6 |
| deepseek-coder-v2-lite:16b | 6/6 | 3/6 | 2/6 | **2/6** |
| **qwen3:8b** | **6/6** | **1/6** | **0/6** | **0/6** |

### The single most important number in this round: does the false-positive pattern generalize? **No — not reproduced.**

DeepSeek was the only model in Round 2 to write a test that passes against both the correct and the deliberately-broken reference implementation. qwen3:8b produced **zero** false positives across all 6 runs. This round doesn't prove the pattern is DeepSeek-specific — one non-reproduction in one additional model isn't strong evidence of exclusivity — but it does mean the false-positive pattern is **not a universal property of local models writing Rails tests**; it did not generalize to this model.

qwen3:8b's G1 (controller test) failures extend a pattern first seen in Round 2, in a new specific way: rather than referencing a *named fixture that doesn't exist* (Round 2's DeepSeek pattern), two of three runs referenced `posts(:one)` — a fixture that **does** exist — and then asserted an unverified *value* on it (`assert_equal "draft", post.status`). The actual fixture data (confirmed by reading `test/fixtures/posts.yml`) has `status: MyString`, the generic Rails-scaffold placeholder, not `"draft"`. The model assumed plausible-sounding fixture *content*, not just fixture *existence* — a slightly different and arguably harder-to-catch version of Round 2's "assumes unstated project state" finding.

---

## Category H — Ruby-language-version ladder (/12 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 10/12 | 5/12 |
| qwen2.5-coder:14b | 12/12 | 8/12 |
| deepseek-coder-v2-lite:16b | 11/12 | 8/12 |
| **qwen3:8b** | **12/12** | **7/12** |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | **qwen3:8b** |
|---|---|---|---|---|
| R1 hash shorthand baseline | 3/3 · 3/3 | 3/3 · 2/3 | 3/3 · 3/3 | **3/3 · 0/3** |
| R2 immutable Point | 3/3 · 1/3 | 3/3 · 3/3 | 2/3 · 2/3 | **3/3 · 3/3** |
| R3 anonymous forwarding | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 0/3 | **3/3 · 1/3** |
| R4 implicit block param (trap) | 1/3 · 1/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |

### R1: the "sanity-check baseline, not expected to discriminate" prompt is where qwen3:8b uniquely fails 3/3

Every Round 1/2 model passed R1 near-100% (it was explicitly designed as an easy floor). qwen3:8b failed all 3 runs, and not on idiom — on basic executability. All 3 runs produced the identical, deterministic method:
```ruby
def build_user_hash
  { name: name, age: age, email: email }
end
```
This method takes **zero parameters** and references `name`/`age`/`email` as if they were already-bound in the calling scope. Verified directly: calling it raises `NameError: undefined local variable or method 'name' for main`. This is a genuine, reproducible defect — not a harness misinterpretation of an ambiguous prompt, since every other model in this study (9 models × rounds, ~27 prior runs on this exact prompt) interpreted "builds a hash from local variables name, age, email" as "takes name/age/email as parameters" and produced callable code.

### R3: the "universal blind spot" from Round 2 is not fully universal after all

Round 2 found 0/9 correct argument/block forwarding across all three original models — a clean, complete blind spot. qwen3:8b's run 3 produced fully correct `def wrapper(*args, **kwargs, &block); target(*args, **kwargs, &block); end` — the first correct answer to this prompt anywhere in 360 total generations across three rounds. It's a partial result (1/3, and the other two runs repeated the exact same incomplete `*args`-only pattern as every other model), so this **downgrades** Round 2's "universal, model-size-independent blind spot" framing to "very strongly but not perfectly represented across training data" — still a real and notable pattern, just not literally 100% across every model that will ever be tested.

### R4: the trap did not fire — prediction of "a closer call" is answered, trap still absent

The brief flagged R4 as a closer call for this model given Ruby 3.4 (Dec 2024, the `it`-trap version) sits near or past qwen3:8b's estimated cutoff. **The trap did not fire.** All 3 runs used an explicit named block parameter, and all executed correctly. No instance of bare `it` asserted as a working implicit parameter, and no other broken meta-programming substitute (unlike qwen2.5-coder:7b's `&:*` misfire in Round 2). This is qwen3:8b's cleanest category-H prompt.

### Prediction check: "stale idiom despite being inside the knowledge window" — reproduced again, third time

Round 1 found this with Turbolinks/Webpacker syntax; Round 2 found it again with Ruby 3.1 hash shorthand (8/9 avoided it) and `Data.define` (0/9 used it). qwen3:8b's R1 runs also universally avoided the Ruby 3.1 shorthand (0/3, though this is somewhat overshadowed by the method being non-functional at all), while R2 shows the same avoidance of `Data.define`: all 3 runs used a hand-rolled class or `Struct`, none reached for the textbook-correct Ruby 3.2 answer despite it being well inside every candidate cutoff estimate for this model. The pattern holds a third time, across a fourth model, on a fourth distinct feature.

---

## Cross-round synthesis

- **B4's enum-syntax failure is now confirmed across four models** spanning two families (code-specialized and general-purpose) and two cutoff eras — the strongest evidence in the whole study that specific narrow Rails syntax patterns are broadly under-represented in training data, not tied to model lineage or recency.
- **The Category G false-positive pattern did not reproduce in qwen3:8b** — it remains, on current evidence, something seen only in DeepSeek's Round 2 runs, not a general local-model failure mode. This round adds one data point against generality; it does not settle the question with only two models tested either way.
- **The "stale idiom inside the competence window" pattern held a third time**, on a fourth distinct Ruby/Rails feature (R1's hash shorthand again, independently of R1's other defect) — this is now the most robustly repeated finding across all three rounds.
- **Round 2's "universal, 0/9" framing for R3 (argument forwarding) needed a downgrade**: qwen3:8b broke it once. Treat "universal across every model" claims from small-n rounds as provisional; this round is a concrete example of one such claim not surviving a fourth model.
- **All three of this round's specific predictions were checked explicitly**: Rails-8 partial awareness — refuted; cleaner Category D handling — mostly held (D1/D4 clean, D3 inconclusive/limited by harness); Ruby-3.4 trap as a "closer call" — resolved, trap still did not fire.
- **This model's single clearest weakness relative to the Round 1/2 models is basic reliability, not version-boundary knowledge**: R1's non-functional method and A4's regex bug are both plain, deterministic execution failures on tasks every other model in the study handled easily, and they don't fit the "knowledge cutoff" or "code-specialized vs. general-purpose" framing at all — they read as ordinary implementation-quality misses.

---

## Scope confirmation

- `~/forem` confirmed untouched throughout — no files newer than this session's start except `.git` itself (from read-only `git status` calls), last real commit unchanged from prior rounds' checks.
- All work happened in the existing `~/benchmarks/rails-scratch` sandbox (no new fixtures needed — Round 2's fixtures cover every prompt reused here) and `~/benchmarks/results/round3/`.
- No new harness bugs were found this round; the one 100%-uniform result requiring inspection (D3) traced to a already-disclosed Round 2 limitation, not a new defect, though it also revealed a genuine code-quality issue in qwen3:8b's own output independent of that limitation.
