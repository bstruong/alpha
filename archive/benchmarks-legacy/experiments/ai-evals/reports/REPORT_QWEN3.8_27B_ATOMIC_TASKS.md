# Qwen 3.8 27B Atomic Task Evaluation Report

**Evaluation Date:** August 19 – 24, 2026  
**Model:** `openrouter/qwen/qwen3.8-27b`  
**Harness / Agent:** `lemans` (v0.2.3) / `miniswen-installed`  
**Target Domain:** Real-world Ruby on Rails SWE atomic benchmark tasks  
**Comparative Baseline:** Llama 3.1 8B (local Ollama)  

---

## 1. Executive Summary

This report documents the performance of **Qwen 3.8 27B** across a benchmark suite of **21 atomic software engineering tasks** in a production-scale Ruby on Rails codebase. Each task was evaluated across 3 independent trials (63 total runs) to measure both capability and repeatability.

### Key Headline Metrics

| Metric | Measured Result | Context |
| :--- | :--- | :--- |
| **Total Evaluation Trials** | **63 runs** | 3 independent trials per task across 21 tasks |
| **Overall Pass Rate** | **76.2%** (48 / 63 passed) | Scored and verified against automated unit/integration suites |
| **Perfect Consistency (3/3)** | **13 tasks (61.9%)** | Succeeded in all three trials |
| **Partial Success (1/3 or 2/3)** | **6 tasks (28.6%)** | Succeeded in at least one trial |
| **Complete Failure (0/3)** | **2 tasks (9.5%)** | Failed all three trials |
| **Total API Cost** | **$77.49** | Average cost of **$1.23 per trial** (~880k tokens/run) |
| **Total Agent Execution Time** | **30.58 hours** (110,079 s) | Average duration of **29.1 minutes** per trial |

---

## 2. Full Task Performance Matrix

| Task Name | Domain / Subsystem | Pass Rate | Avg Steps | Avg In-Tokens | Avg Out-Tokens | Avg Duration | Avg Cost |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `ac-deep-link-return` | ActionController / Redirects | **2/3 (67%)** | 43 | 1,347,139 | 31,896 | 977s | $0.516 |
| `ac-throttle-search` | ActionController / Rate Limiting | **3/3 (100%)** | 50 | 2,175,218 | 41,085 | 1446s | $0.755 |
| `aj-enqueue-after-commit` | ActiveJob / Transaction Hooks | **3/3 (100%)** | 67 | 3,482,118 | 48,965 | 1671s | $1.184 |
| `aj-resumable-cleanup` | ActiveJob / Batch Resumption | **3/3 (100%)** | 68 | 3,834,854 | 59,151 | 1883s | $1.382 |
| `ar-announce-once` | ActiveRecord / Idempotency | **1/3 (33%)** | 83 | 4,650,061 | 63,284 | 2191s | $1.671 |
| `ar-archive-book-access` | ActiveRecord / Soft Delete & ACL | **3/3 (100%)** | 44 | 1,254,655 | 24,458 | 1043s | $0.474 |
| `ar-atomic-import` | ActiveRecord / Import Transactions | **3/3 (100%)** | 51 | 1,868,778 | 38,707 | 1079s | $0.707 |
| `ar-bulk-access-grants` | ActiveRecord / Batch Permissions | **3/3 (100%)** | 59 | 3,296,607 | 62,313 | 2072s | $1.233 |
| `ar-compact-positions` | ActiveRecord / Ordering Gaps | **1/3 (33%)** | 39 | 1,092,947 | 28,924 | 934s | $0.438 |
| `ar-erase-account` | ActiveRecord / Cascade Deletion | **0/3 (0%)** | 80 | 5,859,125 | 72,813 | 2551s | $1.987 |
| `ar-release-recap` | ActiveRecord / Aggregate Reporting | **3/3 (100%)** | 48 | 1,406,036 | 30,186 | 1080s | $0.563 |
| `ar-tenant-isolation` | ActiveRecord / Multi-Tenancy Scopes | **3/3 (100%)** | 88 | 7,061,019 | 76,974 | 3046s | $2.589 |
| `as-purge-embedded-images` | ActiveStorage / Variant Purging | **2/3 (67%)** | 88 | 6,308,827 | 73,687 | 2586s | $2.199 |
| `as-variant-processed-once` | ActiveStorage / Concurrency Locks | **2/3 (67%)** | 98 | 6,521,307 | 72,261 | 2434s | $2.292 |
| `av-toc-cache-per-role` | ActionView / Fragment Caching | **3/3 (100%)** | 94 | 6,695,592 | 82,511 | 2943s | $2.353 |
| `hw-scoped-broadcast` | ActionCable / Scoped Channels | **1/3 (33%)** | 91 | 4,954,729 | 59,299 | 2294s | $1.600 |
| `sec-audit-sweep` | Security / Vulnerability Audit | **3/3 (100%)** | 49 | 2,184,036 | 37,128 | 1164s | $0.792 |
| `sup-cache-library-digest` | ActiveSupport / Key Invalidation | **3/3 (100%)** | 32 | 617,552 | 18,132 | 730s | $0.271 |
| `sup-legacy-conversions` | ActiveSupport / Legacy Serialization | **0/3 (0%)** | 49 | 1,852,211 | 35,697 | 1130s | $0.699 |
| `sup-log-to-terminal` | ActiveSupport::Logger / I/O Redirect | **3/3 (100%)** | 64 | 3,743,319 | 55,886 | 1816s | $1.442 |
| `tst-error-page-flake` | Test Harness / Flake Stabilization | **3/3 (100%)** | 49 | 1,729,035 | 36,852 | 1623s | $0.682 |

---

## 3. Failure Mode Deep-Dive

Only two tasks suffered 100% failure rates (0/3 trials passing). Both failures revealed specific architectural edge cases:

### A. `ar-erase-account` (0/3 passed)
* **Objective:** Completely erase an account and its associated resources while preserving transactional guarantees.
* **Failure Symptom:** `VerifierTest#test_the_book_they_kept_to_themselves_is_gone_whole,_down_to_the_superseded_draft_and_the_search_hits`
* **Root Cause:** The model wrote cascade deletion for top-level records (`User`, `Account`, `Books`) but neglected polymorphic join tables, superseded draft revisions, and asynchronous search index deletion hooks. The verifier confirmed lingering orphaned draft records.

### B. `sup-legacy-conversions` (0/3 passed)
* **Objective:** Maintain backward-compatibility and serialization fidelity for historical data cards across schema version upgrades.
* **Failure Symptom:** `VerifierTest#test_a_book_with_nothing_in_it_still_has_its_card_and_its_archived_copy`
* **Root Cause:** The agent's conversion routine presumed non-empty collections, crashing or returning `nil` when serializing empty books or cards with 0 records.

---

## 4. Local Baseline Comparison: Llama 3.1 8B

A subset of tasks was executed locally against **Llama 3.1 8B** (using Ollama):
* **Production Tasks (`ar-release-recap`, `sup-cache-library-digest`):** 0% pass rate. The model struggled with long-context multi-file navigation, exhausting step limits (90+ steps) without producing valid patches.
* **Sanity Checks (`hello-world`):** Passed 2 out of 5 runs (40%), demonstrating high variance on basic agentic tool calling in Ruby environments.

---

## 5. Artifact Retention & Repository Hygiene

To adhere to repository conventions (`CONVENTIONS.md`):
* **Retained Permanently in Git:**
  - This summary report (`REPORT_QWEN3.8_27B_ATOMIC_TASKS.md`).
  - All 63 code diffs written by the agent (`agent.patch`).
  - All verifier test failure summaries (`checks.json`).
  - Execution metadata and token usage stats (`result.json`).
  - Verifier execution logs (`verifier.log`).
  - Ollama modelfiles and local harness backups (`ai-evals-local/`).
* **Excluded / Discarded:**
  - Ephemeral agent step scratchpads (`trajectory.json` files totaling ~24 MB / ~200k lines of raw JSON) were omitted to preserve Git history health.
