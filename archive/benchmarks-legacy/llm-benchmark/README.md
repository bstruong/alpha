# ASSASSIN LLM Benchmark (Ruby)

Benchmarks local LLMs (via Ollama) for two roles:

1. **Extraction fallback** — statement text → structured JSON (ASSASSIN's
   LLM fallback, used only when deterministic extraction fails)
2. (future) budgeting chat/reasoning — not yet implemented here

It builds a **synthetic ground-truth set** (no real financial data needed),
sends each fixture to each model using Ollama's structured-output schema
enforcement, and scores the results — weighting JSON-validity and
money-exactness because the model is an *untrusted* fallback.

## Requirements

- Ruby 3.2+ (uses `Data.define`; stdlib only — no gems, no `bundle install`)
- [Ollama](https://ollama.com) running locally for the benchmark step
- ~12GB VRAM (RTX 3060) for the candidate models at Q4

## Quick start

```bash
# 1. Generate the synthetic ground-truth fixtures (reproducible with --seed)
bin/generate_fixtures --seed 42

# 2. Review a few pairs to confirm they look like real statements
cat fixtures/chase_bank_2024_01_clean/source.txt
cat fixtures/chase_bank_2024_01_clean/expected.json

# 3. Pull the candidate models (check registry for newer point-releases first)
ollama pull qwen3:14b
ollama pull phi4:14b

# 4. Run the benchmark
bin/benchmark --models qwen3:14b,phi4:14b --runs 3
```

## What "ground truth" means here

A fixture is a pair of files:

```
fixtures/chase_bank_2024_01_clean/
├── source.txt      # statement text the model reads
└── expected.json   # the certified-correct extraction (the answer key)
```

The generator produces both sides from the same canonical `Statement`
object, so the answer key is correct *by construction* — no hand-typing.
You review a sample to confirm realism. Money in `expected.json` is integer
cents (matching ASSASSIN).

### Using real statements instead

Don't feed raw statements to this harness — it has no PII scrubbing, and
the fixtures/logs would contain plaintext sensitive data. If you want
real-document realism, scrub statements through ASSASSIN's Presidio
scrubber first (once it exists), then drop the scrubbed `source.txt` +
a hand-written `expected.json` into a fixture directory. The harness
treats hand-made and generated fixtures identically.

## Fixture coverage

`bin/generate_fixtures` produces 9 fixtures spanning easy → hard:

| Layout | Vendors | Difficulty |
|---|---|---|
| `clean` | Chase, Schwab | Aligned columns, ISO dates |
| `compact` | BofA, Schwab | US dates, dollar signs, terse |
| `messy` | Chase, BofA, Schwab | Wrapped descriptions, footnotes, noise lines |

Edit the `PLAN` array in `bin/generate_fixtures` to change the mix.

## Scoring rules (fixed up front)

| Metric | Rule |
|---|---|
| JSON-valid | Did the response parse without repair? Invalid = all-zero score. |
| Field accuracy | Exact match on institution, account, period start/end. No partial credit. |
| Money exact | Beginning + ending balance cents must match exactly. A hard gate. |
| Txn precision | Correct transactions / extracted transactions (catches hallucinations). |
| Txn recall | Correct transactions / expected transactions (catches misses). |

A transaction matches on **date + amount + kind**. Description is *not*
part of the match key (vendors phrase it inconsistently), but is available
if you want to add fuzzy description scoring later.

## Recommended weighting

Per the benchmark plan, weight the dimensions:

| Dimension | Weight |
|---|---|
| Structured-output accuracy (field + txn + money) | 40% |
| JSON-validity / tool-calling reliability | 25% |
| Inference speed (tok/s) | 20% |
| VRAM fit | 10% |
| Setup simplicity | 5% |

The runner prints the raw per-model table; apply the weights to pick a
winner (the table is intentionally raw so you can re-weight without
re-running).

## Project layout

```
lib/
├── statement.rb            # Statement + Transaction value objects (the truth)
├── statement_generator.rb  # builds synthetic Statement objects
├── text_renderer.rb        # Statement -> source.txt (clean/compact/messy)
├── fixture_writer.rb       # writes source.txt + expected.json pairs
├── ollama_client.rb        # calls Ollama /api/generate with schema enforcement
├── scorer.rb               # grades model output vs answer key
└── benchmark_runner.rb     # orchestrates models x fixtures x runs, reports
bin/
├── generate_fixtures       # CLI: build the ground-truth set
└── benchmark               # CLI: run the benchmark
```

## Notes

- Only one model fits in 12GB VRAM at a time; the runner benchmarks models
  sequentially, so this is fine.
- `temperature: 0` is set to minimize run-to-run variance; the `--runs 3`
  default still measures consistency.
- This harness tests Ollama's **structured-output** path (schema passed as
  the `format` parameter) — the same path ASSASSIN's extraction service
  would use, not raw prompt-only JSON.
```
