# Homelab Model Evaluation Report: Qwen 3.6 35B vs. GLM 4.7 Flash REAP

**Evaluation Date:** October 16, 2026  
**Node:** AM5 Homelab (`watchtower`, `127.0.0.1`)  
**Hardware Profile:** AMD Ryzen 7 9700X (8C/16T, 32 MiB L3) | 32 GB DDR5-6000 CL36 | NVIDIA GeForce RTX 3060 12GB | Samsung 990 Pro NVMe  
**Inference Engine Substrate:** `llama-server` (k3s pod with GPU passthrough and IPC_LOCK `mlock`)  
**Scenario Target:** `qwen36-daily` (3 gate checks + 6 graded challenges)  
**Supervision & Profile:** Alpha Harness `bin/alpha run` with Pi agent supervision (`shipping` profile)

---

## 1. Executive Summary

We conducted comprehensive, head-to-head live evaluation campaigns directly on the AM5 homelab node (`watchtower`) comparing the two primary local open-weights coding models:
1. **`qwen36-coder-hybrid`**: Qwen 3.6 35B MoE (A3B active) with 8 expert layers offloaded to VRAM (`n-cpu-moe = 32`).
2. **`glm47-reap`**: GLM-4.7 Flash REAP 23B MoE (A3B active) with 25% pruned experts and 100% CPU MoE offload.

### Key Results & Verdict

| Model Identity | Engine Preset | Context Window | Total Wall Time | Pass@1 Score | Tasks Passed | Qualification Status (Threshold $\ge 0.70$) |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **GLM-4.7-Flash-REAP-23B-A3B** | `glm47-reap` | 131,072 | 1983.9s | **0.67** | **6 / 9** | ❌ Not Qualified (1 task away) |
| **Qwen 3.6 35B Hybrid** | `qwen36-coder-hybrid` | 262,144 | **445.6s** | **0.56** | 5 / 9 | ❌ Not Qualified |

- **Top Accuracy:** **`glm47-reap` achieved the highest Pass@1 score (67%)**, demonstrating stronger adherence to architectural specifications and clean multi-tenant cache isolation.
- **Top Speed:** **`qwen36-coder-hybrid` completed the full evaluation suite 4.4× faster (445.6s vs. 1983.9s)** due to expert layer VRAM acceleration, sustaining over 50 tok/s decode vs. GLM's 35 tok/s.
- **Codebase Stability:** Across both models and all 18 evaluated task executions, **`bin/rails test` remained 100% green**. Neither model introduced syntax errors, broken fixtures, or test regressions into the underlying repository.

---

## 2. Head-to-Head Task Breakdown & Scorecard

Both models were evaluated on the 9 tasks of the canonical `qwen36-daily` benchmark:

| # | Task | Type | `qwen36-coder-hybrid` | `glm47-reap` | Comparative Analysis |
|:---:|:---|:---:|:---:|:---:|---|
| 1 | `gate-hello` | Gate | ✅ **PASS** (18.0s) | ✅ **PASS** (17.0s) | Both models cleanly executed single-file modification of `HELLO.md`. |
| 2 | `gate-boot` | Gate | ✅ **PASS** (0.0s) | ✅ **PASS** (0.0s) | Unpatched sandbox baseline verification (instant). |
| 3 | `gate-edit` | Gate | ✅ **PASS** (18.0s) | ✅ **PASS** (18.5s) | Both applied seeded structural edits without regressing unit tests. |
| 4 | `empty-card` | Graded | ✅ **PASS** (40.0s) | ✅ **PASS** (122.5s) | Both properly handled empty collection edge cases in model queries. |
| 5 | `spec-wins` | Graded | ❌ **FAIL** (53.0s) | ✅ **PASS** (141.0s) | **GLM Win:** GLM upgraded both model logic and the visible test suite to exact `BigDecimal` arithmetic. Qwen fixed the model but neglected to update the obsolete float assertion. |
| 6 | `library-cache` | Graded | ❌ **FAIL** (15.0s) | ✅ **PASS** (121.5s) | **GLM Win:** GLM correctly scoped the cache key per tenant (`library-digest/#{id}`). Qwen exited after 15s without editing, leaving cross-tenant cache leakage intact. |
| 7 | `audit-three` | Graded | ❌ **FAIL** (139.0s) | ❌ **FAIL** (721.1s) | **Partial GLM Improvement:** GLM passed 2/3 checks (avoiding Qwen's `DoubleRenderError`), but timed out at 720s while attempting to implement SQL wildcard escaping. |
| 8 | `once-only` | Graded | ✅ **PASS** (49.0s) | ❌ **FAIL** (121.0s) | **Qwen Win:** Qwen implemented the single-use idempotency token. GLM deliberated and answered without calling tools. |
| 9 | `erase-account` | Graded | ❌ **FAIL** (113.5s) | ❌ **FAIL** (721.1s) | Both models struggled with complex, multi-model transactional cascades and author anonymization. |

---

## 3. Failure Mode Deep Dive

An analysis of the grader verifier output and container traces revealed distinct failure archetypes:

### Task 5: `spec-wins`
- **Specification:** When an architectural specification mandates `BigDecimal` exact math for money/receipts and an existing test uses loose float deltas (`assert_in_delta 0.3, total, 0.0001`), the specification wins and the test must be updated.
- **Outcome:**
  - `qwen36-coder-hybrid` updated `Receipt.quote` to return `BigDecimal("0.3")`, but left the test file untouched. The verifier asserted `/BigDecimal/ =~ File.read("test/models/receipt_test.rb")` and failed.
  - `glm47-reap` correctly edited both `app/models/receipt.rb` and `test/models/receipt_test.rb`, satisfying all verifier assertions.

### Task 6: `library-cache`
- **Specification:** Library overview digests must be cached for 1 hour, but private books from one user must never be visible to another user.
- **Outcome:**
  - `qwen36-coder-hybrid` failed to recognize the shared cache key bug (`Rails.cache.fetch("library-digest")`) and exited without making changes.
  - `glm47-reap` recognized the multi-tenant vulnerability and scoped the cache key: `Rails.cache.fetch("library-digest/#{id}", expires_in: 1.hour)`.

### Task 7: `audit-three`
- **Specification:** Enforce 3 simultaneous invariants: (1) prevent member role escalation, (2) restrict book deletion to editors and admins, and (3) treat search `%` and `_` as literal data via SQL LIKE escaping.
- **Outcome:**
  - `qwen36-coder-hybrid` added an authorization check in `BooksController#destroy` with `head :forbidden`, but omitted `return`. Rails executed down to `book.destroy!` and threw an `AbstractController::DoubleRenderError`.
  - `glm47-reap` fixed the controller authorization cleanly (passing checks 1 and 2), but entered a repeated deliberation cycle trying to implement SQL wildcard escaping in `BookSearch`, hitting the 720s wall-clock timeout.

### Task 9: `erase-account`
- **Specification:** GDPR-style account erasure requiring transactional cascade deletion of private books and drafts, reassignment of shared books to `"Deleted author"` with `account_id = nil`, and deletion of sign-in records across both `email` and `original_email`.
- **Outcome:**
  - Both models struggled with the multi-model complexity. Qwen exited without tool execution (`no_tools_called`), while GLM timed out attempting to coordinate the changes across multiple associations.

---

## 4. Operational Strategy for Daily Homelab Use

The empirical findings establish clear boundaries for how local open-weights models should be deployed in daily workflows:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   FRONTIER CLOUD AGENTS (Gemini / Claude)              │
│  • System architecture & database schema planning                     │
│  • Decomposing multi-model epics into single-file tasks                │
│  • Resolving complex, multi-service transactional invariants          │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │ Decomposed tasks & isolated specs
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   WATCHTOWER HOMELAB NODE (AM5 + RTX 3060)             │
│  • Local PII & Sensitive Data Scrubbing (Zero Exfiltration)            │
│  • Local Document & OCR Structuring (Paperless-ngx / Immich)          │
│  • Single-responsibility bug fixes & TDD refactors                     │
│  • Overnight batch linting, AST transforms, and test generation        │
└────────────────────────────────────────────────────────────────────────┘
```

### Recommended Workflow Rules

1. **Keep Prompts Scoped to a Single Responsibility:** Do not issue omnibus prompts requiring simultaneous changes across controllers, models, and migrations. Decompose tickets so the local model handles one concern at a time.
2. **Explicitly Target File Paths:** State the exact file to modify (e.g. `Modify only app/models/account.rb to scope the cache key by id`).
3. **Exploit the Homelab Superpowers:**
   - **Zero marginal cost:** Run iterative single-file test cycles freely without token budget anxiety.
   - **Zero data exfiltration:** Route sensitive logs, personal tax documents, invoices, and private credentials through local inference before any sanitized context touches external APIs.

---

## 5. Artifact & Run Trace References

- **Qwen 3.6 Run Report:** [`reports/20261016T215552Z-qwen36-daily.md`](file:///home/user/Projects/alpha/reports/20261016T215552Z-qwen36-daily.md)
- **GLM 4.7 Run Report:** [`reports/20261016T221542Z-qwen36-daily.md`](file:///home/user/Projects/alpha/reports/20261016T221542Z-qwen36-daily.md)
- **Qwen Qualification Artifact:** `/home/user/projects/alpha/qualifications/qwen36-coder-hybrid__shipping.json`
- **GLM Qualification Artifact:** `/home/user/projects/alpha/qualifications/glm47-reap__shipping.json`
- **Canonical Evaluation Database:** Synced in Rails API SQLite mirror (`EvalRun` and `TaskResult` tables).
