# Direct Ruby/Rails Model Benchmark — Round 4 (gemma4:12b-it-q4_K_M)

**Date:** 2026-08-09
**Model:** `gemma4:12b-it-q4_K_M` (7.6 GB per the Ollama library, ~7.4 GB actual pull size), run in default mode via Ollama's `think: false` API parameter — confirmed via log inspection that all 90 generations show `thinking_present=False`.
**VRAM:** measured empirically before proceeding, per the round's hard-stop gate. Baseline (display running on the same RTX 3060, cable not moved): 317 MiB used / 11590 MiB free / 12288 MiB total. With the model loaded (triggered via a real generation call): **8143 MiB used / 3764 MiB free / 12288 MiB total** (`ollama ps` reported the model split 7%/93% CPU/GPU — a handful of layers offloaded to CPU, no effect on output correctness, only speed). 3.7+ GiB of free VRAM remained throughout the run — comfortably above the ~500–800 MiB hard-stop threshold, so generation proceeded without any workaround to `OLLAMA_CONTEXT_LENGTH`/`OLLAMA_KV_CACHE_TYPE`/quantization.
**Sandbox:** `~/Projects/berserker/ruby-rails-model-benchmark/rails-scratch` — same disposable sandbox as Rounds 1–3, confirmed clean (`git status` — nothing to commit) before starting, no drift.
**Scope:** the exact same 30 prompts from Rounds 1–3, reused byte-identical from their `prompts.json` source (diffed to confirm) × 1 model × 3 fresh runs = 90 generations.
**Raw data:** `APPENDIX_ROUND4.md` (all 90 outputs, annotated with scores), `category_c_dump.txt` (Category C qualitative dump), and `scores_a.json` / `scores_b.json` / `scores_d.json` / `scores_e.json` / `scores_f.json` / `scores_g.json` / `scores_h.json`.

## Why this round exists

Rounds 1–3 tested four models spanning two families — the Qwen line (`qwen2.5-coder:7b`, `qwen2.5-coder:14b`, `qwen3:8b`) and DeepSeek (`deepseek-coder-v2-lite:16b`) — and turned up four cross-round patterns repeated with striking consistency. This round tests `gemma4:12b-it-q4_K_M`, a genuinely different model family (Google DeepMind's Gemma line), specifically to see whether those four patterns are properties of "local code-generation models in general" or artifacts of the Qwen/DeepSeek lineage. The harness, prompts, scoring discipline, and sandbox are all unchanged from Rounds 1–3 — only the model differs.

---

## Category A — Generic Ruby (/12 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 9/12 | 6/12 |
| qwen2.5-coder:14b | 12/12 | 9/12 |
| deepseek-coder-v2-lite:16b | 12/12 | 9/12 |
| qwen3:8b | 12/12 | 9/12 |
| **gemma4:12b-it-q4_K_M** | **12/12** | **10/12** |

By prompt — "executes/behavior," both out of 3:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | qwen3:8b | **gemma4:12b** |
|---|---|---|---|---|---|
| A1 word_frequency | 1/3 · 1/3 | 3/3 · 3/3 | 3/3 · 0/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| A2 Stack class | 2/3 · 2/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| A3 safe_divide | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| A4 extract_emails | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 0/3 | **3/3 · 1/3** |

Gemma 4 12B's only Category A miss is A4 (`extract_emails`), and — like qwen3:8b in Round 3 — it's a genuine, reproducible regex bug, not a harness artifact. But it's a *different* bug from qwen3:8b's (which dropped `+` from its character class). Run 1's regex uses the `/i` case-insensitive flag and passes. Runs 2 and 3 both switched to an explicit `[A-Za-z0-9._%+-]` character class for the local part but **dropped the trailing `/i` flag entirely**, leaving the domain-suffix group `[A-Z]{2,}` literally uppercase-only. Since every email in the test text has a lowercase TLD (`.com`, `.co.uk`, `.io`), the regex matches **zero** emails in both failing runs (`got=[]`, verified directly). A clean, deterministic authoring slip: the model reasoned about case-insensitivity for the local part but forgot it also governs the domain-suffix character class once the `/i` modifier was dropped.

---

## Category B — Rails 7.1-era idioms (/15 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 14/15 | 11/15 |
| qwen2.5-coder:14b | 15/15 | 12/15 |
| deepseek-coder-v2-lite:16b | 15/15 | 12/15 |
| qwen3:8b | 14/15 | 10/15 |
| **gemma4:12b-it-q4_K_M** | **15/15** | **12/15** |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | qwen3:8b | **gemma4:12b** |
|---|---|---|---|---|---|
| B1 migration | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| B2 User validations | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 2/3 | **3/3 · 3/3** |
| B3 PostsController#publish | 2/3 · 2/3 | 3/3 · 3/3 | 3/3 · 3/3 | 2/3 · 2/3 | **3/3 · 3/3** |
| B4 Order enum + validate:true + scope | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 0/3 | **3/3 · 0/3** |
| B5 admin/articles routes | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |

### B4 fails 3/3 again — but for the first genuinely new reason in four rounds

This is the headline finding of the round; see the dedicated pattern-check section below. Short version: **Gemma 4 12B is the first model across five to write the *correct* Rails 7.0+ enum calling convention** (`enum :status, {...}, validate: true` — positional name, positional hash, keyword options) in all 3 runs, verbatim identical each time. Every prior model in the study wrote the broken pre-7.0 form (`enum status: {...}, validate: true`) and crashed with `ArgumentError` before the code ever really executed. Gemma 4's code *does* execute — and then fails for a completely different, deeper reason: it defines the enum with **integer values** (`pending: 0, paid: 1, ...`) against a `status` column that this sandbox's schema defines as a **string** column (`t.string "status"`, unchanged since Round 1). Verified directly by reproducing the exact generated code:

```
status_before_type_cast="1"
status=nil
respond_to_paid?=true
paid?=false
```

The integer `1` gets stored as the string `"1"`, but Rails' enum lookup table is keyed by the *original* declared value type (integer `1`), so `"1"` never matches back to `:paid` — `status` reads back as `nil`, and every predicate method (`paid?`, etc.) silently returns `false`. Worse, the `validate: true` inclusion check that's supposed to reject bad values doesn't fire either — assigning `status: "bogus_status"` is accepted with no error, because the same type mismatch appears to disable the enum's own value-validity guard. This is a genuinely new, deeper diagnostic result that no prior model's B4 output ever surfaced, because no prior model's code got past the syntax error far enough to expose it.

B1/B2/B3/B5 are otherwise clean, and B3 in particular is gemma4's only clean 3/3 sweep among all models tested on that prompt (every other model in the study had at least one B3 miss).

---

## Category C — Rails-8-boundary knowledge check (qualitative, /9 runs, not scored into correctness)

| Model | C1 background job | C2 authentication | C3 asset pipeline |
|---|---|---|---|
| qwen2.5-coder:7b | Sidekiq+ActiveJob, confident | Devise, confident | Sprockets, confident (stale Turbolinks in 2/3) |
| qwen2.5-coder:14b | Sidekiq+ActiveJob, confident | Devise, confident | Sprockets, confident (stale Webpacker in 1/3) |
| deepseek-coder-v2-lite:16b | Sidekiq+ActiveJob, confident | Devise, confident | Sprockets, confident |
| qwen3:8b | Sidekiq+ActiveJob, confident | Devise, confident | Sprockets, confident |
| **gemma4:12b-it-q4_K_M** | **ActiveJob (+optional Sidekiq), confident** | **Devise, confident (with hallucinations)** | **Propshaft-or-Sprockets, explicitly hedged** |

**C1 (background job):** all 3 runs use `ActiveJob` + a dedicated job class + `after_create_commit`, framing Sidekiq as one example adapter (`config.active_job.queue_adapter = :sidekiq`) rather than assuming it outright. No mention of Rails 8's Solid Queue. Materially Rails-7-era, same as every prior model, just slightly more adapter-agnostic in phrasing.

**C2 (authentication):** all 3 runs reach for Devise — zero mention of Rails 8's built-in `rails generate authentication` generator (Nov 2024), so still Rails-7-locked in substance. But this round's C2 also contains the round's most concentrated cluster of hallucinations: run 3 writes `gem 'devine', '~> 4.9'` — an actual **misspelling of the gem name itself** (should be `devise`) — plus a fabricated `Rails._load_config!` call and a fabricated Devise DSL macro `devise_every :sessions do ... end` (the real macro is `devise_for :users`). None of these appeared in any prior round's C2 output.

**C3 (asset pipeline) — the one place Category C broke pattern:** **all 3 runs explicitly name Propshaft as a live option** ("using **Propshaft** or **Sprockets**" / "modern **Sprockets** or **Propshaft** defaults"), and run 1 contains an outright, unprompted version hedge: *"Note: This assumes a modern Rails 7+ structure."* This is the **first explicit Rails-version hedge and the first Propshaft mention anywhere in the study** — 36 prior Category-C generations across 4 models, zero hedging, zero Propshaft. See the headline-finding section below for the full analysis; in short, the awareness is real but shallow — the actual generated *code* in all 3 runs is pure legacy Sprockets configuration (`config.assets.compile`, `config.assets.precompile`, a Sprockets `manifest.js`), which is meaningless under Propshaft. The model knows Propshaft's *name* but not what changes about the underlying task.

---

## Category D — Rails 7.2 boundary (/12 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 12/12 | 8/12 |
| qwen2.5-coder:14b | 12/12 | 11/12 |
| deepseek-coder-v2-lite:16b | 12/12 | 11/12 |
| qwen3:8b | 12/12 | 9/12 |
| **gemma4:12b-it-q4_K_M** | **12/12** | **11/12** |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | qwen3:8b | **gemma4:12b** |
|---|---|---|---|---|---|
| D1 transaction-safe job enqueue | 3/3 · 1/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| D2 YJIT config | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| D3 Ruby-version-floor initializer | 3/3 · 2/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 0/3 | **3/3 · 3/3** |
| D4 after_commit/after_rollback | 3/3 · 2/3 | 3/3 · 2/3 | 3/3 · 2/3 | 3/3 · 3/3 | **3/3 · 2/3** |

D3 is a clean sweep here: all 3 runs correctly use `Gem::Version.new(RUBY_VERSION) < Gem::Version.new(...)`, avoiding qwen3:8b's Round 3 type-mismatched `Rails.version`-vs-`RUBY_VERSION` confusion entirely. Stated floor is `3.2.0` in all 3 runs — stricter than the actual Rails 7.2 minimum (Ruby 3.1), so the harness's classifier labels it "other" rather than "7.2-aware" (which only pattern-matches a literal `3.1`-prefixed string) — but functionally this is *more* current than necessary, not stale, and should be read as version-aware, just conservative.

D4's one miss (run 2) is Category D's most interesting single result: the model **flatly and confidently denies that `after_rollback` is a real ActiveRecord callback** — *"Rails doesn't have a native `after_rollback` callback like it does for `after_commit`"* and *"since `after_rollback` isn't a native ActiveRecord callback"* — and steers toward a manual `rescue ActiveRecord::Rollback` workaround instead. This is false: `after_rollback` has been a documented, native transactional callback since Rails 3.0, sitting right alongside `after_commit` in the same API. Runs 1 and 3 (same prompt, same model) both correctly define and use `after_rollback` with no hedging at all — so this is a genuine run-to-run reliability gap on a basic factual claim, not a systematic knowledge gap. Categorized separately from ordinary hallucination (inventing a fake method) as its mirror image: **confidently denying a real one exists.**

---

## Category E — Gem-referencing tasks (/9 runs per model)

| Model | Executes | Behaviorally correct | Hallucinated API calls |
|---|---|---|---|
| qwen2.5-coder:7b | 9/9 | 6/9 | 0 |
| qwen2.5-coder:14b | 9/9 | 5/9 | 1 |
| deepseek-coder-v2-lite:16b | 9/9 | 6/9 | 0 |
| qwen3:8b | 9/9 | 6/9 | 2 |
| **gemma4:12b-it-q4_K_M** | **9/9** | **3/9** | **4** |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | qwen3:8b | **gemma4:12b** |
|---|---|---|---|---|---|
| E1 Kaminari pagination | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| E2 ActiveStorage `has_one_attached` | 3/3 · 3/3 | 3/3 · 2/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 0/3** |
| E3 ransack fuzzy search | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 0/3 | **3/3 · 0/3** |

**E2 is gemma4's single worst result in the entire study, and it's this round's most concentrated hallucination cluster: 3/3 runs invent a different, wrong variant of `has_one_attached`, verified verbatim in the raw output each time:**
- Run 1: `has_one_attached_record :cover_image`
- Run 2: `has_one_attached_scanner :cover_image`
- Run 3: `has_one_attached_attached :cover_image`

All three follow the exact shape `has_one_attached_<spurious-suffix>` — the model clearly "knows" the real method's stem (`has_one_attached`) but appends a plausible-sounding, entirely fabricated suffix each time, rather than using the real bare method name. This is a new hallucination *shape* not seen in Rounds 1–3 (those hallucinations were either wrong gems entirely — Paperclip's `validates_content_type_of` — or singular/plural slips like `store_accessors`). No prior model in the study has ever failed E2 this way; E2 was a clean 3/3-across-the-board pass for every one of the four prior models.

E3 (ransack) fails 3/3 again — the fifth model in a row — but with a notably more sophisticated *shape* of failure than Rounds 1–2's original three models. Two of three runs show real awareness that Ransack 4.x requires an allowlist (`ransackable_attributes`), which none of the original three Round 1/2 models ever demonstrated at all:
- Run 1's extracted block never defines the allowlist (a different, non-allowlist block from the same response was selected as the model's own primary offering — the response hedges across four different partial approaches within one answer, and the harness picks the first `class Article` block, which happens to be the weakest one).
- Run 2 correctly defines `ransackable_attributes` but then calls a fabricated macro, `ransackable__scopes_for :content_search` (double underscore, not a real Ransack or Rails method) as a bare statement — a genuine hallucination.
- Run 3 never modifies the `Article` model at all, and its closing line explicitly (and incorrectly) claims *"No extra code needed in model; Ransack handles this automatically"* — a confident, false claim directly contradicting Ransack 4.x's actual mandatory-allowlist security requirement.

E1 remains a clean sweep for every model in the study — pagination is the one Category E prompt no model has ever gotten wrong.

---

## Category F — Convention-heavy Rails patterns (/15 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 15/15 | 12/15 |
| qwen2.5-coder:14b | 15/15 | 10/15 |
| deepseek-coder-v2-lite:16b | 15/15 | 14/15 |
| qwen3:8b | 15/15 | 12/15 |
| **gemma4:12b-it-q4_K_M** | **14/15** | **10/15** |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | qwen3:8b | **gemma4:12b** |
|---|---|---|---|---|---|
| F1 has_many :through | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| F2 polymorphic association | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| F3 callback timing (shipped_at) | 3/3 · 2/3 | 3/3 · 1/3 | 3/3 · 2/3 | 3/3 · 0/3 | **3/3 · 0/3** |
| F4 Concern extraction | 3/3 · 1/3 | 3/3 · 0/3 | 3/3 · 3/3 | 3/3 · 3/3 | **2/3 · 1/3** |
| F5 strong params | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |

**F3 fails 3/3 — a fourth model to hit 0/3 on this prompt — but gemma4 splits its three runs across two genuinely distinct mistakes:**
- Run 1 uses `status_changed?` inside an `after_save` callback. `status_changed?` is a real dirty-tracking method, but it's the **wrong one for this hook**: Rails swaps "current changes" for "previous changes" once a save completes, so `status_changed?` (querying *current* changes) always evaluates `false` from inside `after_save` — a well-known, specific Rails gotcha. The guard silently never fires (`set_on_transition=false`).
- Runs 2 and 3 correctly recognize the gotcha above ("`changed?` is no longer available in `after_save` callbacks as the change has already been persisted") and reach for `saved_change?(:status)` instead — but **that exact method signature doesn't exist**. The real API is `saved_change_to_attribute?(:status)` or the dynamic `saved_change_to_status?`; `saved_change?(:status)` is a plausible-sounding hallucination, confirmed by the harness's `NoMethodError: undefined method 'saved_change?'`. So two of three runs demonstrate *correct conceptual knowledge* of the after_save dirty-tracking gotcha while still failing on the exact method name.

**F4's one execution failure (run 3) is a genuine syntax error, not a logic bug or a harness artifact** — confirmed by direct reproduction. The generated Concern module contains a line of literal, un-commented prose dropped directly into the code body: `years/months/days logic is not needed here, just the core functionality.` inside the `included do...end` block. Ruby's parser chokes on this exactly as expected (`syntax error, unexpected local variable or method, expecting 'do' or '{' or '('`) — a categorically different and more severe failure than any prior model's F4 misses (which were all real-but-wrong API calls or structural placement mistakes, never literal natural-language text inside a code fence).

---

## Category G — Test-writing (2 prompts × 3 runs = 6 runs)

| Model | Well-formed | Passes vs. correct | Passes vs. broken | **False positive** |
|---|---|---|---|---|
| qwen2.5-coder:7b | 6/6 | 0/6 | 0/6 | 0/6 |
| qwen2.5-coder:14b | 5/6 | 1/6 | 0/6 | 0/6 |
| deepseek-coder-v2-lite:16b | 6/6 | 3/6 | 2/6 | **2/6** |
| qwen3:8b | 6/6 | 1/6 | 0/6 | 0/6 |
| **gemma4:12b-it-q4_K_M** | **6/6** | **2/6** | **0/6** | **0/6** |

### The single most important number in this round, now a third data point: still not reproduced

Gemma 4 12B produced **zero** false positives across all 6 runs — the third model out of five (after qwen2.5-coder:14b/7b and qwen3:8b) to fully avoid the false-positive pattern DeepSeek alone showed in Round 2. The running tally is now **1 model out of 5** (DeepSeek only) ever having produced this specific worst-class failure. This continues to weaken, without eliminating, the case that it's a general local-model failure mode — it looks increasingly DeepSeek-specific, though a sample of one positive case out of five models still can't rule out recurrence in a sixth.

**A second harness bug was found and fixed on this round's G2, following the same discipline that caught four bugs in Round 2 and disclosed one non-bug in Round 3.** All 3 initial G2 runs came back uniform (`FAIL: test malformed / did not run`, identical NameError-family traceback each time) — the trigger for mandatory inspection per this benchmark's standing rule. Root cause: gemma4's G2 responses bundle a model-file snippet *and* the test file inside a **single** fence (unlike G1, which always used separate fences per file):
```ruby
# app/models/user.rb
class User < ApplicationRecord
  ...
end

# test/models/user_test.rb
require "test_helper"
class UserTest < ActiveSupport::TestCase
  ...
```
The harness (unmodified from Round 3) writes the *entire* extracted block verbatim as the test file. Since the `class User < ApplicationRecord` re-open sits *before* `require "test_helper"` in the same file, Ruby evaluates it first — before Rails/Zeitwerk has booted — and raises `NameError: uninitialized constant ApplicationRecord`, a pure ordering artifact with nothing to do with the test's actual quality. This is structurally identical to Round 2's disclosed bug #2 (multi-file content bundled in one fence, there affecting Categories E/F). Fixed the same way: `execute_g.py` now slices the extracted block down to the actual test file, starting at the `require "test_helper"` line (falling back to the `class ...Test <` declaration, then the untouched block if neither pattern is found). After the fix, G2 resolved to 1 real pass, 1 real pass, 1 real fail — all three genuinely well-formed and behaviorally scored, none touching the false-positive path. The fix is local to Round 4's copy of the script; Rounds 1–3's numbers are untouched.

G1 (controller test) fails 0/3 for three distinct, all-genuine reasons, none of them false positives:
- Run 1: `NoMethodError: undefined method 'assert_redirect_to'` — a hallucinated near-miss of the real Rails/Minitest assertion, which is `assert_redirected_to`.
- Run 2: `ActiveModel::UnknownAttributeError: unknown attribute 'content' for Post` — the model invented a `content` column on `Post` that was never mentioned in the prompt and doesn't exist in the sandbox's schema, a variant of the Round 2/3 "assumes unstated project state" pattern, but about schema shape rather than fixture data.
- Run 3: one real assertion failure (checks for `div.alert` in the response body of a *redirect* response, which never renders that HTML at all — a conceptual test-design miss) plus the same `assert_redirects_to` (plural variant) hallucination as run 2's cousin.

G2's one post-fix failure (run 3) is a distinct, lower-severity test-writing mistake: it asserts `assert_includes @user.errors[:email], :blank` — checking a *symbol* against `errors[:email]`, which actually returns human-readable message strings (`"can't be blank"`). The correct API for symbol-based checks is `errors.of_kind?` or `errors.details[:email]`. All 5 of run 3's assertion failures follow this exact same string-vs-symbol confusion.

---

## Category H — Ruby-language-version ladder (/12 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 10/12 | 5/12 |
| qwen2.5-coder:14b | 12/12 | 8/12 |
| deepseek-coder-v2-lite:16b | 11/12 | 8/12 |
| qwen3:8b | 12/12 | 7/12 |
| **gemma4:12b-it-q4_K_M** | **12/12** | **9/12** |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite | qwen3:8b | **gemma4:12b** |
|---|---|---|---|---|---|
| R1 hash shorthand baseline | 3/3 · 3/3 | 3/3 · 2/3 | 3/3 · 3/3 | 3/3 · 0/3 | **3/3 · 3/3** |
| R2 immutable Point | 3/3 · 1/3 | 3/3 · 3/3 | 2/3 · 2/3 | 3/3 · 3/3 | **3/3 · 3/3** |
| R3 anonymous forwarding | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 1/3 | **3/3 · 0/3** |
| R4 implicit block param (trap) | 1/3 · 1/3 | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 | **3/3 · 3/3** |

### R1 and R2 together: the clearest break from the established stale-idiom pattern in the whole study

R1 (Ruby 3.1 hash shorthand) is functionally correct 3/3 — gemma4 takes `name`/`age`/`email` as **parameters** (unlike qwen3:8b's Round-3 zero-arg, non-callable version) and builds `{ name: name, age: age, email: email }`. This is still the *pre-3.1 explicit style*, matching the established stale-idiom pattern exactly (4/4 prior models also avoided the shorthand) — so R1 alone changes nothing.

**R2 is where the pattern actually breaks.** All 3 runs use `Point = Data.define(:x, :y)` — the textbook-correct Ruby 3.2 (Dec 2022) idiom the prompt was purpose-built to elicit. This is the **first time in four rounds and 12 total R2 generations across the other four models that any model used `Data.define`.** Round 2 found 0/9; Round 3 found 0/3 (qwen3:8b used a hand-rolled class or `Struct` in all 3 runs). Gemma 4 12B reaches for it immediately and consistently, correctly explains the immutability and value-equality semantics in prose, and the code passes the behavioral check 3/3. One minor blemish: run 3's prose states `Data` was "introduced in Ruby 3.0" — factually wrong (it's 3.2) — while runs 1 and 2 both correctly say 3.2; a run-to-run inconsistency in an otherwise-correct explanation, not a code-level defect.

### R3: the "downgraded-from-universal" blind spot holds again, 0/3, with a new interaction worth flagging

R3 (argument/block forwarding) fails 3/3. Runs 1 and 2 use `*args`-only forwarding (the same incomplete pattern every model in the study defaults to), but additionally define their **own example `target` method** directly in the response as illustrative usage code — which, because the harness's driver pre-defines its own `target(*args, **kwargs, &block)` stub and then appends the model's full extracted block afterward, gets silently clobbered by the model's own redefinition. This changes the *failure message* (`got args=nil kwargs=nil block=nil`, since the model's own simplified `target` returns `nil` from a bare `puts`) but not the *verdict*: even without this collision, `*args`-only forwarding would drop keyword arguments and the block regardless, so the underlying result is unaffected — worth disclosing per this benchmark's transparency discipline, but not a scoring bug. Run 3 explicitly uses `*args, **kwargs` (closer to correct) but still omits `&block`, and its own demo `target` redefinition triggers `ArgumentError: wrong number of arguments` when the driver's real test call reaches it. Net: 0/3, consistent with Round 3's "very strongly but not perfectly represented" framing (qwen3:8b's lone 1/3 success remains the only correct R3 answer anywhere in the study).

### R4: the trap still did not fire, and gemma4 shows a new, more self-aware failure texture

All 3 runs use an explicit named block parameter (`{ |n| n * 2 }`) and pass. No instance of bare `it` anywhere. Run 2 is worth quoting directly for its texture: after writing the (correct, explicit) code, the model explicitly second-guesses itself — *"in Ruby, to use a block without naming the variable while still performing an operation on it, you must name it"* — a hedge that is functionally true for pre-3.4 Ruby but reads as the model recognizing it can't satisfy the literal "without naming the parameter" instruction and defaulting safely rather than fabricating a broken construct. This is a distinct behavioral texture from any prior model's R4 output (none hedged this explicitly) — cautious-but-correct, rather than confidently wrong.

---

## Gemma 4 12B against the four established cross-round patterns

### 1. B4 enum-syntax bug — partially breaks, in the most informative way possible

Every prior model (4/4, spanning code-specialized and general-purpose lines) failed B4 3/3 by writing the broken pre-Rails-7.0 `enum status: {...}, validate: true` calling convention and crashing with `ArgumentError` before the code meaningfully executed. **Gemma 4 12B is the first model to write the correct calling convention** (`enum :status, {...}, validate: true`) in all 3 runs. B4 still fails 3/3 — but now for a substantively different, deeper reason (the integer-enum-values-against-a-string-column type mismatch detailed above) that no prior model's output ever survived long enough to expose. Read narrowly, "B4 fails 3/3" is now 5/5 models. Read accurately, the specific *syntax* bug this pattern was built to catch is now 4/5 — broken by exactly the kind of new-family model this round was designed to test against.

### 2. Stale-idiom-inside-competence-window — breaks cleanly on R2, holds on R1

R2 (`Data.define`) is a clean break: 3/3 correct usage of the current idiom, the first such result anywhere in the study (0/12 previously). R1 (hash shorthand) still holds the pattern (3/3 pre-3.1 style). So this pattern is now confirmed *not* universal — it held for 3 of 4 prior models' worth of repetition and one specific feature (R1), but did not generalize to a different specific feature (R2) tested on the same model. The pattern should be read going forward as "idiom-specific training-data underrepresentation," not a general property of "newer idioms vs. older idioms."

### 3. Gem-specific API hallucination on Category E — holds and intensifies

E3 (ransack) fails 3/3 for a fifth consecutive model — the single most robust pattern in the whole study, now proven across every model tested regardless of family, size, or era. This round adds the highest hallucination count yet on Category E (4, versus qwen3:8b's previous high of 2), concentrated on a genuinely new failure surface: E2 (ActiveStorage), previously a 12/12 clean sweep across all four prior models, now fails 3/3 with three distinct fabricated `has_one_attached_*` variants. The pattern generalizes beyond ransack specifically to "any single well-known-but-not-maximally-central gem method surface" — E2's core method is about as central as ActiveStorage gets, and it still fell.

### 4. Category G false-positive — still not reproduced; now 1 model out of 5

Zero false positives in 6 runs. The running count stands at 1/5 models (DeepSeek only, Round 2) ever having produced this failure class. Continues to look DeepSeek-specific rather than a general local-model property, though the sample remains small.

---

## Headline finding

**This round's most consequential result is not a single number but a shape: Gemma 4 12B is simultaneously the first model to correctly solve two long-standing "universal" failures (B4's syntax, R2's `Data.define`) and the first to introduce a brand-new, previously-unseen failure surface (E2's `has_one_attached_*` hallucination family, a prompt that was a flawless 12/12 across every prior model).** Neither direction is small. This is exactly the kind of result a genuinely different model family should produce if the four established patterns really were partly artifacts of Qwen/DeepSeek's shared training-data gaps rather than universal properties of "local code models": a different family clears some of those specific gaps while opening others that the Qwen/DeepSeek lineage never showed. The secondary headline is Category C's C3: the first explicit Rails-version hedge and the first spontaneous Propshaft mention anywhere in the study (36 prior generations, zero), even though the awareness turned out to be shallow (name-level, not implementation-level — the generated code stays pure Sprockets regardless of which pipeline is named). Taken together: gemma4 is measurably *more knowledgeable* about specific narrow syntax/idiom boundaries this round's prompts were built to probe, but not more *reliable* — its overall behavioral-correctness rate is middling (see cross-round synthesis below), and it introduces the round's highest hallucination count on Category E and the study's first "asserts a real feature doesn't exist" failure (D4). Better narrow knowledge and worse aggregate reliability are not in tension; this round is direct evidence they can coexist in the same model.

---

## Cross-round synthesis

- **Aggregate behavioral-correctness rate for gemma4:12b, summed across every scored category (A/B/D/E/F/H; G and C excluded as non-comparable formats): 65/93 ≈ 70%.** This sits in the middle of the pack — better than qwen2.5-coder:7b's clearly weakest showing, comparable to the other three models, not a step change in either direction. The interesting story this round is in *where* the misses land (a new hallucination surface, a new type-mismatch bug) rather than in the aggregate rate.
- **B4's enum-syntax failure needed a footnote for the first time in four rounds.** The specific narrow calling-convention bug that was 4/4-universal is now 4/5; the prompt as a whole remains 5/5-failing, but for reasons that stopped being uniform. This is the single clearest evidence in the whole study that "universal across every model tested" claims from small-n rounds need continual re-testing against genuinely different model families, not just more models from the same lineage.
- **The "stale idiom inside the competence window" pattern is now confirmed non-universal on a per-feature basis.** It held a fourth time on R1 (hash shorthand) but broke cleanly on R2 (`Data.define`) — the same model, the same round, two adjacent Category-H prompts probing similar "does the model reach for the modern idiom" territory, opposite results. Future framing should treat each idiom as independently under- or over-represented in training data, not assume a single "recency" axis governs all of them together.
- **Gem-API hallucination is now the most robust, most model-independent pattern in the study (5/5 models on E3) and just gained its most striking single example (E2's 3/3 fabricated-suffix cluster, on a prompt every other model aced).** This looks less like a knowledge-boundary issue and more like a structural property of how these models handle "guess a plausible Rails-DSL-shaped identifier" when the real one isn't confidently recalled — worth testing explicitly in any future round with a model chosen specifically to probe it.
- **The Category G false-positive pattern remains DeepSeek-specific on current evidence (1/5 models), though this round did surface a second harness bug in the same structural family as Round 2's (multi-file content bundled into a single fence), this time on Category G rather than E/F** — a reminder that the "100%-uniform-result triggers mandatory inspection" discipline continues to earn its keep on every round tested so far, independent of which model is being run.
- **This round's new-model-family design intent was validated**: at least two of the four established patterns (B4's syntax specifically, and the "stale idiom" framing generally) turned out to be partially lineage-specific rather than universal, which is exactly the kind of finding a same-lineage fifth model (a `qwen3:14b` or another DeepSeek variant, say) would have been structurally unable to produce.

---

## Scope confirmation

- `~/forem` confirmed untouched: `find ~/forem -newer <session-start marker>` (marker written at the very start of this session, before any model interaction) returned **zero files** on the first check, including `.git`. A second check run at the very end of this session (after this report's own read-only `git status` scope-check inside `~/forem`) shows only `.git` itself as newer — the same "no real content touched, only `.git`'s own directory mtime bumped by a read-only `git status` call" pattern disclosed in every prior round's scope confirmation, and directly attributable to this session's own inspection command, not to any generation or execution activity. Pre-existing local modifications visible in `~/forem`'s `git status` (a handful of tracked-file edits and untracked opencode-related files) all predate this session and were not touched or created by it.
- All generation and execution happened inside the existing `rails-scratch` sandbox (confirmed clean via `git status` before starting, confirmed clean via `git checkout -- . && git clean -fd` after every single trial, confirmed clean again at the end) and `results/round4/` / `reports/round4/`.
- Two harness issues were investigated this round, following the "100%-uniform failure triggers mandatory inspection" rule:
  1. **E2's three uniform-shaped-but-not-identical hallucinated method names** (`has_one_attached_record`/`_scanner`/`_attached`) were verified as genuine model output, not an extraction artifact, by reading the raw JSON directly — no harness change needed.
  2. **G2's 3/3 uniform `NameError: uninitialized constant ApplicationRecord` failures were a real harness bug** (multi-file content bundled in a single fence, model-file preamble executing before `require "test_helper"` boots Rails) — fixed in `results/round4/execute_g.py` via a new `extract_test_code()` helper, disclosed in full in the Category G section above. The fix is local to this round's copy of the script and does not alter any prior round's recorded numbers.
  3. Several other apparently-uniform results (F4's stray-prose syntax error, F3's dirty-tracking bugs, B4's type-mismatch) were individually reproduced by hand outside the harness (writing the exact generated code into the sandbox and running `bin/rails runner`/`bin/rails test` directly) to confirm they were genuine model defects, not scoring artifacts, before being written up above.
