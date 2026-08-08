# Direct Ruby/Rails Model Benchmark — Round 2

**Date:** 2026-08-08
**Models:** `qwen2.5-coder:7b`, `qwen2.5-coder:14b`, `deepseek-coder-v2:16b-lite-instruct-q4_K_M`
**Sandbox:** `/home/brian/benchmarks/rails-scratch` (same sandbox as Round 1; Ruby 3.3.0, Rails 7.1.6)
**Scope:** 18 new prompts across 5 new categories (D: Rails 7.2 boundary, E: gem-referencing, F: convention-heavy Rails patterns, G: test-writing, H: Ruby-language-version ladder) × 3 models × 3 fresh runs = 162 generations.
**Raw data:** `APPENDIX_ROUND2.md` (all 162 full outputs, annotated with scores) and `scores_d.json` / `scores_e.json` / `scores_f.json` / `scores_g.json` / `scores_h.json`. Round 1's report and appendix remain at `~/benchmarks/results/REPORT.md` / `APPENDIX.md`, untouched.

**Methodology note — harness bugs found and fixed mid-run (disclosed per the same discipline as Round 1):**
1. A code-fence regex treated a bare ` ``` ` as ambiguously both open *and* close, mis-pairing a closing fence with the next opening fence whenever a non-ruby-tagged block (` ```bash `, ` ```erb `) sat between two ruby blocks — silently capturing prose as fake "code." Replaced with a line-based state-machine parser.
2. Some gem-tutorial-style responses (Category E) packed multiple files (model / migration / view / controller / routes) into a *single* fence, separated only by `# path/to/file` comments. The generic "grab the matching block" extraction picked up the whole multi-file blob. Fixed by adding a class-scoped regex pass (`class Article ... end`) after the marker match, mirroring the technique already used for Category F's multi-class responses.
3. Category E1's pagination check counted commas across the *entire* rendered HTML page (including the layout's importmap JSON, which is comma-heavy) instead of just the article titles — made every run look unpaginated regardless of actual behavior. Fixed with an unambiguous delimiter.
4. The `Order` fixture was missing a `shipped_at` column needed by F3, causing a uniform false failure. Added via migration, committed to the sandbox baseline.

All four were caught by the same discipline used throughout: a 100%-uniform failure rate across every model was treated as a signal to inspect the harness before trusting the result, not as evidence all three models share a defect. Every category below reflects the corrected runs. `~/forem` was not touched (confirmed again at the end of this document).

---

## Category D — Rails 7.2 boundary (fine-grained, /12 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 12/12 | 8/12 |
| qwen2.5-coder:14b | 12/12 | 11/12 |
| deepseek-coder-v2-lite:16b | 12/12 | 11/12 |

By prompt — "executes/behavior," both out of 3:

| Prompt | qwen 7b | qwen 14b | deepseek-lite |
|---|---|---|---|
| D1 transaction-safe job enqueue | 3/3 · 1/3 | 3/3 · 3/3 | 3/3 · 3/3 |
| D2 YJIT config | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 |
| D3 Ruby-version-floor initializer | 3/3 · 2/3 | 3/3 · 3/3 | 3/3 · 3/3 |
| D4 after_commit/after_rollback | 3/3 · 2/3 | 3/3 · 2/3 | 3/3 · 2/3 |

**D1 nuance:** qwen2.5-coder:7b's two "failures" are actually the *safest* code in the whole prompt — 2/3 runs used an `after_commit` callback to defer the job enqueue (exactly the Rails-7.2-safe pattern), but never defined the literal `process_order` method the prompt asked for, so my harness (checking `respond_to?(:process_order)`) correctly marked it a task-completion miss despite the underlying pattern being right. qwen2.5-coder:14b landed on the same after_commit-deferred pattern in 2/3 runs while still satisfying the literal method contract. **DeepSeek never once used after_commit-deferral** — all 3 runs enqueued the job directly inside the transaction body, the naive pre-7.2 assumption — despite passing the harness's literal-method check by defining `process_order`. So on the one Category-D prompt with a real behavioral safety distinction, the models split exactly along an axis the harness's simple pass/fail doesn't fully capture; see the raw appendix for the actual code.

**D3:** every model that stated a specific minimum-Ruby-version string used something from `2.5`–`2.7`, none used `3.1` (the actual Rails 7.2 floor) — consistent 7.1-only framing across all three models, no divergence.

**D4:** all three models occasionally registered only one of the two requested callbacks (commit *or* rollback, not both) in 1/3 runs each — a generic completeness miss, evenly distributed, not tied to any version boundary.

---

## Category E — Gem-referencing tasks (/9 runs per model)

| Model | Executes | Behaviorally correct | Hallucinated API calls |
|---|---|---|---|
| qwen2.5-coder:7b | 9/9 | 6/9 | 0 |
| qwen2.5-coder:14b | 9/9 | 5/9 | 1 |
| deepseek-coder-v2-lite:16b | 9/9 | 6/9 | 0 |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite |
|---|---|---|---|
| E1 Kaminari pagination | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 |
| E2 ActiveStorage `has_one_attached` | 3/3 · 3/3 | 3/3 · 2/3 | 3/3 · 3/3 |
| E3 ransack fuzzy search | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 0/3 |

**Round 1 found zero hallucinated gem APIs in 108 generations and explicitly flagged that as contrary to the pre-registered industry expectation. Round 2's Category E — designed specifically to stress a real gem's method surface — finally surfaces one:** `qwen2.5-coder:14b`, E2 run 1, wrote `validates_content_type_of` on the `Article` model. That method belongs to **Paperclip** (a pre-ActiveStorage attachment gem, long deprecated), not ActiveStorage — a genuine cross-gem hallucination, not a syntax slip.

**E3 (ransack) failed 9/9 across every model, every run** — but not from hallucination. All three correctly called `Article.ransack(...)` with real Ransack syntax; every failure was `RuntimeError: Ransack needs Article attributes explicitly allowlisted`, i.e. none of the models knew about Ransack 4.x's mandatory `ransackable_attributes` security allowlist (introduced 2023, plausibly right at or past some cutoffs). One DeepSeek run (E3 run 1) went further and referenced `Article::PgSearch` — the model substituted a *different* well-known gem's naming convention despite the prompt explicitly saying "using the ransack gem." This is a real, if narrow, hallucination: inventing an integration for a gem that was never asked for and isn't installed.

---

## Category F — Convention-heavy Rails patterns (/15 runs per model)

| Model | Executes | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 15/15 | 12/15 |
| qwen2.5-coder:14b | 15/15 | 10/15 |
| deepseek-coder-v2-lite:16b | 15/15 | 14/15 |

By prompt:

| Prompt | qwen 7b | qwen 14b | deepseek-lite |
|---|---|---|---|
| F1 has_many :through | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 |
| F2 polymorphic association | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 |
| F3 callback timing (shipped_at) | 3/3 · 2/3 | 3/3 · 1/3 | 3/3 · 2/3 |
| F4 Concern extraction | 3/3 · 1/3 | 3/3 · 0/3 | 3/3 · 3/3 |
| F5 strong params (nested, no over-permit) | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 |

**F4 is the standout result of the round: DeepSeek 3/3, qwen2.5-coder:14b 0/3** — the *larger* Qwen model did worse than both the smaller Qwen and DeepSeek on the same prompt. Its three failures were each a different structural mistake: `undefined local variable or method 'boolean'` (used bare migration-DSL-style syntax inside a model file), `undefined method 'scope' for module Archivable::ClassMethods` (declared `scope` outside the required `included do` block), and `undefined method 'add_column'` (literally wrote a schema-migration call inside `app/models/concerns/`). qwen2.5-coder:7b's F4 failures include a genuine **hallucinated method**: `store_accessors` (plural) — the real ActiveRecord method is `store_accessor` (singular), used for JSON-column virtual attributes, and has nothing to do with declaring a default on a real boolean column. The model reached for a real-sounding but wrong/nonexistent API to solve a problem that didn't call for it.

**F5 (strong params, the over-permitting check) passed 9/9** — no model over-permitted a nested `commentable_id`/`commentable_type` or a top-level `user_id`, and all correctly wrapped with `.require(:article)`. Clean result, no idiom concerns.

**F1/F2 (has_many :through, polymorphic) passed 9/9 each** — both are textbook, high-frequency Rails patterns, and both were letter-perfect across all three models every time. Worth naming as the categories' cleanest results, in contrast to F3/F4.

---

## Category G — Test-writing (2 prompts × 3 models × 3 runs = 18 runs)

| Model | Test well-formed (ran at all) | Passes vs. correct impl | Passes vs. broken impl | **False positive** (passes both) |
|---|---|---|---|---|
| qwen2.5-coder:7b | 6/6 | 0/6 | 0/6 | 0/6 |
| qwen2.5-coder:14b | 5/6 | 1/6 | 0/6 | 0/6 |
| deepseek-coder-v2-lite:16b | 6/6 | 3/6 | 2/6 | **2/6** |

**This category surfaced the single worst-class failure in either round: a test that passes against both the correct implementation and a deliberately-broken one.** DeepSeek produced this twice (G1 runs 2 and 3). Root cause, verified against the raw code: the generated test only asserted the redirect and the flash message text — it never checked `published_at`, which is the exact field the prompt asked to test and the exact field my "broken" reference implementation omits. A test that never exercises the behavior it's nominally testing will pass regardless of whether that behavior is implemented — this is worse than a test that fails to run, because it actively signals false confidence.

Beyond the false positives, G1 (controller-action test) showed two more distinct failure modes:
- **Wrong test framework entirely:** qwen2.5-coder:14b run 2 wrote full RSpec syntax (`RSpec.describe`, `let`, `sign_in`, FactoryBot's `create(:user)`) despite the prompt explicitly saying "Write a **Minitest** integration or controller test." This is a plain instruction-following miss, not a knowledge gap — the model clearly knows RSpec, just not that it was asked for something else.
- **Assumed unstated project state:** 4/9 G1 runs referenced either a named fixture that doesn't exist (`posts(:unpublished)`) or FactoryBot's `create(:post, ...)` (not installed in this sandbox) rather than creating explicit test data inline (`Post.create!(...)`). Writing tests "blind" (without seeing the actual project's fixtures/factories) is inherent to this eval's no-tool-calling design, but a more defensive model would create its own test data rather than assume infrastructure it never observed — this is a legitimate, reportable convention gap, not an artifact of unfair test conditions.

G2 (model-validation test) had a cleaner failure mode: most runs' tests ran and executed real assertions against the reference `User` model but got specific expectations wrong (wrong error-message text, wrong assertion count) rather than failing to run at all — a lower-severity, more "normal" test-writing quality gap.

---

## Category H — Ruby-language-version ladder (plain `ruby`, /9 runs per prompt)

| Prompt | Behaviorally correct (all models) | Idiom used |
|---|---|---|
| R1 hash shorthand baseline | 8/9 | **8/9 used pre-3.1 explicit style** (`name: name`); only 1/9 (DeepSeek, once) used the Ruby 3.1 shorthand |
| R2 immutable Point (`Data.define`) | 6/9 | **0/9 used `Data.define`** — all reached for `Struct.new` or a hand-rolled class instead |
| R3 anonymous arg/block forwarding | **0/9** | 9/9 used incomplete `*args`-only forwarding — none used `**kwargs`, `&block`, or the Ruby 3.2 `...` syntax |
| R4 implicit block param (the trap) | 7/9 (2 broken-but-not-trapped) | **0/9 triggered the `it`-trap** |

### The Category H R4 trap: did NOT fire

None of the 27 Category-H runs (nor any other run in this benchmark) ever produced bare `it` as an implicit block parameter. 7/9 R4 runs used an explicit named parameter (`{ |n| n * 2 }`); the remaining 2 (both qwen2.5-coder:7b) didn't use a block at all — they wrote `numbers.map(&:*)`, a broken attempt at symbol-to-proc that **crashes with `ArgumentError` when actually executed** (verified directly: `[1,2,3].map(&:*)` raises `wrong number of arguments (given 0, expected 1)`), and one of those two runs additionally included a fabricated inline comment claiming the (nonexistent, crashing) output would be `[2, 4, 6, 8, 10]`. That fabricated-comment behavior is worth naming on its own — a confidently-stated, specific, wrong claim about what code does — but it is a different and less severe failure than the R4 trap the prompt was built to catch. **The specific severity-flagged failure mode (asserting a genuinely nonexistent Ruby 3.4-only feature as if it worked) did not occur in any of the three models.**

### R1 and R2: the Round 1 stale-idiom pattern recurs, strongly

Round 1's headline surprise was qwen2.5-coder using pre-Rails-7.0 Turbolinks/Webpacker idioms despite Rails 7.0 being well inside its claimed cutoff — evidence that "inside the competence window" doesn't mean "will use the current idiom." Category H reproduces that exact pattern on plain Ruby, twice, more starkly:
- **R1** (Ruby 3.1 hash shorthand, shipped Dec 2021): 8/9 runs across all three models defaulted to the old `{name: name, age: age, email: email}` form even though the prompt's phrasing ("builds a hash from local variables") is close to a textbook trigger for the shorthand.
- **R2** (`Data.define`, shipped Dec 2022, i.e. before even DeepSeek's estimated Nov-2023 cutoff): **zero** of nine runs across all three models used it for a textbook "immutable value object" prompt — the single cleanest and most on-the-nose use case `Data.define` was designed for. All nine reached for older, less precise patterns instead, and two of the resulting objects (qwen2.5-coder:7b, both non-`Data.define` runs) weren't actually immutable at all — the models didn't just pick an older idiom, several of them didn't even deliver on the "immutable" part of the prompt with the idiom they did pick.

### R3: a universal blind spot, matching Round 1's B4 enum-syntax pattern

Round 1's clearest single finding was that all three models, regardless of size or cutoff, failed identically on the Rails 7.1 `enum` calling-convention change — a narrow syntax detail apparently under-represented across all three training sets rather than a capacity or recency issue. R3 reproduces that shape exactly on plain Ruby: **100% of runs, across all three models, forwarded arguments with `*args` only**, silently dropping keyword arguments and blocks. None used `**kwargs`/`&block` explicitly, and none used Ruby 3.2's anonymous `...` forwarding. Model size bought nothing here, same as Round 1's B4.

### DeepSeek's predicted Ruby-3.3 divergence did not clearly appear

The Round 2 brief predicted Category H was "the one boundary where DeepSeek and the two Qwen models are predicted to actually diverge," given DeepSeek's ~Nov-2023 cutoff sits just before Ruby 3.3's Dec-2023 release. That divergence did not show up as expected: DeepSeek was the *only* model to ever produce the Ruby 3.1 shorthand (R1), performed identically to qwen2.5-coder:14b on R2's behavioral-correctness count, and tied everyone else at 0/9 on R3. Where DeepSeek did stand out on Category H, it was in the *opposite* direction from the prediction — not "correctly avoiding a too-new feature," but a real API-misunderstanding crash (`private_constant :x, :y`, R2 run 2) attempting to force immutability through a completely unrelated Ruby method. The predicted cutoff-driven split did not materialize; the actual differentiator in this category was ordinary implementation-quality variance, not version knowledge.

---

## Cross-round synthesis

- **Round 1 concluded "no hallucinated gem/API calls anywhere in 108 generations," explicitly against the pre-registered expectation.** Round 2's Category E, purpose-built to probe real gem method surfaces, **falsifies that as a general claim**: `validates_content_type_of` (Paperclip method misapplied to ActiveStorage), `store_accessors` (nonexistent plural form of `store_accessor`), one model's unprompted substitution of PgSearch's naming for a ransack task, and `private_constant` misapplied to instance attributes are four distinct, verified hallucinations/API-misunderstandings across Round 2's 180 generations. The honest updated conclusion: these models don't hallucinate on *common, everyday* Rails/Ruby core APIs (Round 1's finding still holds for that scope), but they do hallucinate or badly misapply APIs once a task requires reaching into a specific gem's less-central method surface — exactly the scope Round 1 never tested.
- **The "stale idiom inside the claimed competence window" pattern, first seen in Round 1 (Turbolinks/Webpacker), is now a repeated, robust finding, not a one-off.** It recurred in Category H (R1 hash shorthand, R2 `Data.define`) with even starker numbers (0/9 and 1/9 use of the current idiom despite full-cutoff availability) than the original Round 1 example.
- **The "universal blind spot regardless of model size" pattern, first seen in Round 1 (B4's enum syntax), also recurred exactly** in Category H's R3 (argument/block forwarding), reinforcing that a subset of narrow syntax patterns are simply under-represented across all three training sets rather than being a recency or capacity issue.
- **Category G (test-writing) uncovered a failure class neither round had previously scored: a false-positive test that passes against broken code.** This is arguably more consequential for real-world use than any single wrong-code generation, since a developer trusting the test would ship the regression it failed to catch.

---

## Scope confirmation

- `~/forem` confirmed untouched: no files newer than this session's start except `.git` itself (from read-only `git status` calls), and its last real commit predates this session by weeks.
- All work happened in `~/benchmarks/rails-scratch` (same disposable sandbox as Round 1, extended with new fixture models/gems on top of Round 1's baseline, each addition committed) and `~/benchmarks/results/round2/` (raw outputs, scores, this report).
- Four harness bugs were found, fixed, and disclosed above; every category's numbers reflect the corrected runs, not the original buggy ones.
