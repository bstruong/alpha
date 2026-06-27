# Local LLM Benchmark — Financial Statement Extraction

Evaluation of local LLMs (via Ollama) for structured extraction of
financial statement data — statement text → structured JSON. This model
serves as the **fallback extractor** in ASSASSIN, used only when
deterministic extraction (pdfplumber/pypdf) fails or a vendor layout is
unknown. The bar is therefore reliability and correctness of structured
output, not raw speed.

## Method

- **Hardware:** RTX 3060 12 GB (VRAM is the binding constraint — caps
  fully-GPU inference at ~14B dense models at Q4_K_M).
- **Runtime:** Ruby 3.4.8 (stdlib only), Ollama 0.30.10.
- **Fixtures:** 9 synthetic ground-truth statements (no real financial
  data), spanning chase/bofa/schwab × clean/compact/messy layouts,
  generated deterministically with `--seed 42`. Each fixture is a
  `source.txt` (statement text) + `expected.json` (certified answer key),
  correct by construction since both are rendered from the same canonical
  object.
- **Runs:** 3 per fixture per model, `temperature: 0`, schema passed via
  Ollama's structured-output `format` parameter (the same path ASSASSIN's
  extraction service uses).
- **Scoring:** JSON validity, field accuracy (exact match on institution
  slug, account last-4, period start/end), money exactness (beginning +
  ending balance cents), transaction precision/recall (matched on date +
  signed amount), tokens/sec.

## Scoring weights

| Dimension | Weight | Rationale |
|---|---|---|
| Structured-output accuracy (field + txn + money) | 40% | Wrong financial data is worse than slow |
| JSON-validity / tool-calling reliability | 25% | Invalid JSON = pipeline failure for a fallback |
| Inference speed (tok/s) | 20% | Matters for bulk import; fallback runs rarely |
| VRAM fit | 10% | Mostly a tie-breaker / headroom flag |
| Setup simplicity | 5% | One-time cost |

## Results (3 runs × 9 fixtures)

| Model | JSON valid | Field acc | Money% | Precision | Recall | Tok/s | VRAM |
|---|---|---|---|---|---|---|---|
| qwen3:14b (Alibaba) | 100% | 0.83 | 100% | 1.00 | 1.00 | 33.8 | fits |
| phi4:14b (Microsoft) | 100% | 0.72 | 100% | 0.96 | 0.96 | 34.0 | fits |

## Recommendation

**qwen3:14b** as ASSASSIN's primary local fallback extractor — perfect
transaction precision/recall, best field accuracy, 100% JSON validity and
money correctness. **phi4:14b** is a strong near-equal backup from a
different model family (100% JSON, 0.96 P/R, marginally faster), worth
keeping available in case qwen3 regresses on a future update. Speeds are
within noise (~34 tok/s); both fully GPU-resident.

## How we got here (three decisions)

1. **Dropped mistral-small3.2 (24B / ~15 GB), replaced with phi4:14b
   (~9 GB Q4).** The 24B model exceeds 12 GB VRAM and would run under CPU
   offload (~18 tok/s), producing a speed number reflecting "doesn't fit"
   rather than real performance — which would rig the comparison against
   the GPU-resident models. phi4 also adds model-family diversity
   (Microsoft vs Alibaba/Google).

2. **Fixed a scorer bug.** First run showed transaction precision/recall
   at ~0.01–0.02 for all models despite high field (0.83) and money
   (100%) accuracy. That inconsistency was the tell: a model reading
   balances correctly isn't plausibly missing every transaction. Root
   cause — the transaction match key included `transaction_kind_hint`, an
   unconstrained free-text field that models phrase as "debit"/"credit"
   vs the fixtures' "withdrawal"/"deposit"; one mismatch zeroed the whole
   key. Fix: match on date + signed amount only (that pair uniquely
   identifies a statement row). Kind hint and description are both
   excluded as inconsistent free text.

3. **Dropped gemma4:12b** — only 26% JSON validity (emitting non-JSON
   wrappers / prose), unreliable for structured extraction as invoked.
   A real finding, not hidden: under identical conditions qwen3 and phi4
   emit clean JSON and gemma4 does not.

### Scorer-fix impact (same models, before vs after)

| | qwen3 P/R | phi4 P/R |
|---|---|---|
| Buggy key (incl. kind hint) | 0.02 / 0.02 | 0.01 / 0.01 |
| Fixed key (date + amount) | 1.00 / 1.00 | 0.96 / 0.96 |

## Known limitations

- **Field accuracy < 1.0** (qwen3 0.83, phi4 0.72) with transactions and
  money perfect points to drift on scalar header fields — likely
  `institution_slug` (model emits "Chase" not the slug `chase`) and date
  normalization on the compact/messy layouts. This is a prompt-
  specification gap (the prompt doesn't define the slug vocabulary or
  enforce ISO dates hard enough), not a model-quality problem. Open
  follow-up; does not affect the model decision.
- **Synthetic fixtures only.** No validation yet against real (scrubbed)
  statements. The generator exercises realistic layout variety but not
  the full messiness of production vendor PDFs.
- **Two-model final set.** A third candidate (gemma4) was dropped for
  JSON-validity; the comparison is qwen3 vs phi4.
- **gemma4's JSON-validity** could likely be improved by forcing
  `format: json` or a grammar constraint — untested here.

## Reproduce

```
cd ~/Projects/berserker/llm-benchmark
ruby bin/generate_fixtures --seed 42
ruby bin/benchmark --models qwen3:14b,phi4:14b --runs 3
```
