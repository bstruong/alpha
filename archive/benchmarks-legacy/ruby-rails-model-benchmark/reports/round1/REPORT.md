# Direct Ruby/Rails Model Benchmark Report

**Date:** 2026-08-08
**Models:** `qwen2.5-coder:7b`, `qwen2.5-coder:14b`, `deepseek-coder-v2:16b-lite-instruct-q4_K_M` (via local Ollama, raw prompt-in/code-out, no tool-calling)
**Sandbox:** `/home/user/benchmarks/rails-scratch` (Ruby 3.3.0, Rails 7.1.6)
**Method:** 12 prompts (4 generic-Ruby / 5 Rails-7.1 / 3 Rails-8-boundary) × 3 models × 3 fresh runs each = 108 generations, all captured raw before scoring. Category A executed with plain `ruby`; Category B executed inside the Rails sandbox (migrations run and rolled back, model/controller files applied and reverted, integration tests run via `bin/rails test`) with `git checkout -- . && git clean -fd` between every trial. Category C scored qualitatively only (no execution expected or required).
**Raw data:** `APPENDIX.md` (all 108 full outputs) and `scores_a.json` / `scores_b.json` (per-run execution results) in the same directory. Nothing here should be taken on faith — spot-check against those files.

A methodology note on the harness itself: two of my own execution-harness bugs surfaced during Category B (a migration-filename mismatch, and a stale `minitest` gem conflicting with Rails 7.1.6's test runner). Both were root-caused, fixed, committed to the sandbox baseline, and the full Category B suite was re-run from clean before any scoring below — see the "harness note" in each affected row if relevant. All numbers below reflect the corrected runs.

---

## Category A — Generic Ruby (execution + behavioral correctness, /12 runs per model)

| Model | Executes w/o error | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 9/12 | 6/12 |
| qwen2.5-coder:14b | 12/12 | 9/12 |
| deepseek-coder-v2-lite:16b | 12/12 | 9/12 |

By prompt — each cell is "executes-without-error / behaviorally-correct", both out of 3 runs:

| Prompt | qwen 7b | qwen 14b | deepseek-lite |
|---|---|---|---|
| A1 word_frequency | 1/3 · 1/3 | 3/3 · 3/3 | 3/3 · 0/3 |
| A2 Stack class | 2/3 · 2/3 | 3/3 · 3/3 | 3/3 · 3/3 |
| A3 safe_divide | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 3/3 |
| A4 extract_emails | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 |

## Category B — Rails 7.1-era idioms (/15 runs per model)

| Model | Executes w/o error | Behaviorally correct |
|---|---|---|
| qwen2.5-coder:7b | 14/15 | 11/15 |
| qwen2.5-coder:14b | 15/15 | 12/15 |
| deepseek-coder-v2-lite:16b | 15/15 | 12/15 |

By prompt — each cell is "executes-without-error / behaviorally-correct", both out of 3 runs:

| Prompt | qwen 7b | qwen 14b | deepseek-lite |
|---|---|---|---|
| B1 migration (add status+index) | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 |
| B2 User validations | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 |
| B3 PostsController#publish | 2/3 · 2/3 | 3/3 · 3/3 | 3/3 · 3/3 |
| B4 Order enum + validate:true + scope | 3/3 · 0/3 | 3/3 · 0/3 | 3/3 · 0/3 |
| B5 admin/articles routes | 3/3 · 3/3 | 3/3 · 3/3 | 3/3 · 3/3 |

**B4 failed for every model, every run** — see failure-pattern section below; this is the single most consistent and most interesting finding in the whole run.

## Category C — Rails-8-boundary knowledge check (qualitative, expected-fail by design, not scored into the above)

| Model | C1 background job | C2 authentication | C3 asset pipeline |
|---|---|---|---|
| qwen2.5-coder:7b | Sidekiq+ActiveJob, confident | Devise, confident | Sprockets, confident (2/3 runs used stale pre-Rails-7 `data-turbolinks-track`) |
| qwen2.5-coder:14b | Sidekiq+ActiveJob, confident | Devise, confident | Sprockets, confident (1/3 runs mixed in stale Webpacker `javascript_pack_tag`) |
| deepseek-coder-v2-lite:16b | Sidekiq+ActiveJob, confident | Devise, confident | Sprockets, confident |

All 27/27 Category C runs across all three models and all three prompts landed on the Rails-7-era answer (Sidekiq/ActiveJob, Devise, Sprockets) with **zero hedging** — no model ever wrote anything like "this depends on your Rails version" or flagged uncertainty about which generator/gem is current. See the confidence-framing section below for detail and verbatim phrasing.

---

## Notable failure patterns

### 1. Universal, 100%-reproducible: Rails 7.1 enum syntax collision (`enum status: {...}, validate: true`)
Every model, every run of B4, failed with `ArgumentError: Enum values true must be either a non-empty hash or an array` (or, in DeepSeek's case, a downstream `no such table` error stemming from the same root cause aborting the `Order` class body). The generated code consistently looked like:
```ruby
enum status: { pending: 0, paid: 1, shipped: 2, cancelled: 3 }, validate: true
```
This is the **pre-Rails-7.0 enum calling convention** (`enum column: values`), which Ruby 3's keyword-argument coalescing turns into a single `**options` hash where `status` and `validate` become sibling keyword entries rather than `validate:` binding to the new `enum(name, values, **options)` signature Rails 7.0+ actually expects (`enum :status, {...}, validate: true`). All three models correctly *know the `validate: true` option exists* (a genuine Rails-7.1-specific detail, called out explicitly in the prompt) — the failure is purely a stale calling convention layered under real feature knowledge. This is a clean example of "confidently wrong" *inside* the models' claimed competence window, not a knowledge-boundary failure.

### 2. Hallucinated/incorrect method-return-type bug (DeepSeek, A1)
DeepSeek's `word_frequency` implementation:
```ruby
def word_frequency(text)
  text.downcase.scan(/\b\w+\b)
      .group_by { |word| word }
      .transform_values(&:size)
      .sort_by { |_, count| -count }
end
```
`sort_by` on a Hash returns an **Array of `[key, value]` pairs, not a Hash** — missing a trailing `.to_h`. This broke the prompt's explicit "returns a hash" contract in all 3/3 runs, consistently. Not a hallucinated API per se (every method called is real), but a systematic Ruby-semantics miss on a commonly-taught idiom.

### 3. Syntax-level generation errors (qwen2.5-coder:7b only, A1)
Two of three A1 runs from the 7B model produced code that doesn't even parse:
- Run 1: `text.downcase.scan(/\b\w+\b).each_with_object(...)` — the regex literal is missing its closing `/` delimiter, so the parser consumes the rest of the line as part of the regex and throws a syntax error.
- Run 2: `scan(/\b[\w']+\b')` — a stray trailing `'` inside the regex delimiter.
This is the smallest model in the set producing literally unparseable Ruby, not just semantically wrong Ruby — a distinct and more severe failure mode than anything seen from the 14B or DeepSeek models.

### 4. `safe_divide` — technically non-crashing, semantically wrong (both qwen models, A3, 6/6 runs)
Both qwen models wrote `a.to_f / b.to_f` inside `rescue ZeroDivisionError / rescue TypeError` blocks. Ruby's `Float#/` never raises `ZeroDivisionError` (it returns `Infinity`), and `"a".to_f` silently coerces to `0.0` rather than raising `TypeError`. The rescue clauses are therefore dead code: `safe_divide(10, 0)` and `safe_divide(10, "a")` both silently return `Infinity` instead of the requested `nil`-with-warning contract. This is a great illustration of the two-separate-checks distinction the eval was designed to catch: **it executes without error, but does not do what was asked.** DeepSeek avoided this by using `raise TypeError` explicitly / integer-preserving division and passed cleanly (3/3).

### 5. No hallucinated gem APIs were observed
Despite this being flagged in the eval design as the expected industry-wide failure mode for local models on Ruby/Rails, none of the 108 outputs invoked a gem method, ActiveRecord finder, or Rails helper that doesn't actually exist. Every failure traced to either (a) a real API used with wrong/stale syntax (the enum case), (b) a genuine Ruby-semantics gap (the Hash/Array and Float-coercion cases), or (c) outright unparseable syntax. Worth noting explicitly since it runs against the pre-registered expectation.

---

## Category C: confidence framing (qualitative)

Across all 27 runs (3 prompts × 3 models × 3 runs), **not one response hedged on Rails version**. No model produced language resembling "this may differ depending on your Rails version" or "if you're on Rails 8, use X instead" — every answer was written as if there were exactly one correct, current approach. Representative phrasing:

- qwen2.5-coder:7b, C2 run3: *"That's it! You now have user authentication in your Rails application using Devise."* — flat, closing-statement confidence, no caveat.
- qwen2.5-coder:14b, C1 run1: full Sidekiq initializer with `Sidekiq.configure_server`/`configure_client` connection-pool boilerplate, presented as current best practice with no acknowledgment this is an older idiom even within the Sidekiq/Rails-7 world.
- deepseek-coder-v2-lite, C3 run2/run3: terse, code-only responses (`config.assets.precompile += %w(...)`) with no prose hedge at all — the shortest, most confident-by-omission answers of the three models.

This is a uniform result, not a per-model difference: all three models exhibit the same "confidently-wrong-but-plausible" posture the eval was designed to detect, with no meaningful variation in hedging behavior between them. The differentiator between models in Category C is not confidence framing but **internal consistency** — see the surprise below.

---

## Surprises relative to the knowledge-cutoff predictions

1. **Biggest surprise — stale pre-Rails-7 idioms surfaced *inside* the supposedly-known Rails 7.1 window.** In C3, `qwen2.5-coder:7b` used `data-turbolinks-track` (2/3 runs) and `qwen2.5-coder:14b` used `javascript_pack_tag` alongside it once — both are Webpacker/Turbolinks-era APIs that were replaced by Turbo (`data-turbo-track`) and Importmap (`javascript_importmap_tags`) starting with the Rails 7.0 release in December 2021. Our own Rails 7.1.6 scaffold's default-generated layout confirms the current idiom (`app/views/layouts/application.html.erb` uses `data-turbo-track` and `javascript_importmap_tags`). This isn't a knowledge-boundary miss (Rails 7.0 is well inside qwen2.5-coder's ~June 2024 cutoff) — it's dataset-weight contamination from older Rails 5/6 tutorials, on a topic the model should have gotten right.
2. **DeepSeek's Nov-2023 cutoff prediction ("Ruby 3.3/Rails 7.1 thin at best") did not visibly hold it back on Category B.** It scored on par with or better than the qwen models on execution/behavioral correctness in Category B (12/15 behavior-pass, tied with the 14B and ahead of the 7B), and it was the *only* model that avoided the A3 `safe_divide` Float-coercion trap. Given the pre-registered expectation that this model's Rails-7.1 knowledge would be "thin," its actual code quality on Rails-flavored tasks was not visibly worse than the newer-cutoff qwen models.
3. **The B4 enum failure was universal and equally severe across all three models** — no model, regardless of size or cutoff, used the correct Rails 7.0+ `enum :name, values, **options` calling convention. Model size (7B vs. 14B) bought nothing here; this looks like a genuinely under-represented pattern across all three training sets rather than a capacity or recency issue.
4. **No hallucinated gem/API calls anywhere in 108 generations** — contrary to the pre-registered expectation that this would be the dominant, industry-typical failure mode for local models on Ruby/Rails, every failure traced to real APIs used incorrectly rather than invented ones.

---

## Scope confirmation

- No test prompts, evaluations, or generated code were ever written into or executed against `~/forem` — confirmed via `git status`/mtime checks before and after this run, only `.git`'s own metadata (from read-only `git status` calls) shows any touch, and the repo's last real commit predates this session.
- All generation and execution happened against the disposable `~/benchmarks/rails-scratch` sandbox and `~/benchmarks/results/` (raw outputs, scores, this report), fully separate from `~/forem`.
- Two harness bugs (migration filename derivation, minitest version pin) were found and fixed mid-run, both committed to the sandbox's baseline commit for reproducibility; the affected Category B trials were re-run in full after the fix, not patched in place.
