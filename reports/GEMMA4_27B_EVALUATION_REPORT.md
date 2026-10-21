# Gemma 4 27B / 26B-A4B Instruct (`gemma4-27b`) Evaluation Report: Email Triage Battery

**Evaluation Date:** October 17, 2026  
**Node:** AM5 Homelab (`watchtower`)  
**Hardware Profile:** AMD Ryzen 7 9700X (8C/16T, 32 MiB L3) | 32 GB DDR5-6000 CL36 | NVIDIA GeForce RTX 3060 12GB | Samsung 990 Pro NVMe  
**Model Under Test:** `gemma4-27b` (`bartowski/google_gemma-4-26B-A4B-it-GGUF`, `Q4_K_M`, 15.86 GB file size, 25.2B total / 4B active parameters MoE)  
**Run ID:** [`20261017T175836Z-email-triage`](../results/runs/20261017T175836Z-email-triage/summary.json)  
**Qualification:** [`qualifications/gemma4-27b__triager__shipping.json`](../qualifications/gemma4-27b__triager__shipping.json) (`role: triager`, Pass@1 = `1.00`)

---

## 1. Executive Summary & Complete Comparative Scorecard

Google's **Gemma 4 27B / 26B-A4B Instruct** was evaluated against the standardized 4-task `email-triage` benchmark scenario on Watchtower. 

**Result:** Gemma 4 27B achieved a **perfect 1.00 (4/4) Pass@1** in **22.9 seconds total wall time**. 

By utilizing `--cpu-moe` hybrid offloading, the model placed its 4B active attention/shared tensors in GPU VRAM (**only 3.26 GB VRAM**, leaving **8.63 GB VRAM free**) while holding routed experts across host DDR5 RAM (**~15 GB RAM**). Despite running experts across the system memory bus, the sparse 4B active parameter footprint enabled an impressive decode speed of **~32.8 tok/s** (~1.12s per email), matching the speed of dense 12B/14B models while delivering heavy-weight reasoning depth.

### Comprehensive Head-to-Head Scorecard Across All Models

| Model Identity | Architecture | Parameter Scale | Quantization | Peak VRAM | Host RAM | Pass@1 (Accuracy) | 4-Task Total Wall Time | Mean Triage Latency (Task 1) | Effective Decode Speed | Triager Qualification |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **`gemma4-4b`** | Dense Edge | 4.8B (E4B) | `Q4_K_M` | 3.77 GB | 0 GB (100% VRAM) | ✅ **1.00 (4/4)** | ⚡ **10.1s** | ⚡ **0.52s / email** (`2.1s` / 4 emails) | **~64.8 tok/s** | ✅ **QUALIFIED** |
| **`gemma4-12b`** | Dense Mid | 12.0B | `Q4_K_M` | 8.64 GB | 0 GB (100% VRAM) | ✅ **1.00 (4/4)** | **22.4s** | **1.04s / email** (`4.1s` / 4 emails) | **~33.5 tok/s** | ✅ **QUALIFIED** |
| **`gemma4-27b`** | **Sparse MoE** | **25.2B (4B Act)** | **`Q4_K_M`** | **3.26 GB** | **15.0 GB** (DDR5) | ✅ **1.00 (4/4)** | **22.9s** | **1.12s / email** (`4.5s` / 4 emails) | **~32.8 tok/s** | ✅ **QUALIFIED** |
| **`qwen25-coder-14b`** | Dense | 14.7B | `Q4_K_M` | 10.47 GB | 0 GB (100% VRAM) | ✅ **1.00 (4/4)** | 19.7s | 0.99s / email (`3.9s` / 4 emails) | ~34.5 tok/s | ✅ **QUALIFIED** |
| **`qwen36-coder-hybrid`** | MoE (A3B) | 35.0B | `UD-Q4_K_M` | 11.20 GB | 20.2 GB (DDR5) | ✅ **1.00 (4/4)** | 17.0s | 0.88s / email (`3.5s` / 4 emails) | ~40.6 tok/s | ✅ **QUALIFIED** |
| **`glm47-reap`** | MoE (A3B) | 23.0B | `Q4_K_M` | 5.20 GB | 16.5 GB (DDR5) | 0.75 (3/4) | 19.5s | 0.79s / email (`3.2s` / 4 emails) | ~30.2 tok/s | ✅ **QUALIFIED** |

---

## 2. Task-by-Task Empirical Breakdown

### Task 1: `triage-classify-priority` (Structured Multi-Account Triage)
* **Grader:** `Alpha::Grader::JsonSchema` | **Thinking Level:** `none`
* **Wall Time:** **4.466s** (Prompt: 710 tokens | Completion: 127 tokens | Decode: **28.4 tok/s**)
* **Per-Email Latency:** **1.12 seconds per email** across the 4 synthetic accounts.
* **Output Sample:**
  ```json
  {
    "account": "homelab-alerts@watchtower.local",
    "category": "production_alert",
    "urgency": "P1",
    "action_required": true,
    "summary": "Critical storage capacity exhaustion on NVMe pool and GPU PCIe bus reset causing alpha-llama deployment crash-loop on watchtower node.",
    "tags": [
      "watchtower",
      "k3s",
      "nvme",
      "gpu",
      "production_outage"
    ]
  }
  ```
* **Verdict:** ✅ **PASS**. Perfect triage ranking; identified root-cause hardware anomalies and categorized as a high-severity production outage.

---

### Task 2: `audit-security-phishing` (Header & Phishing Audit)
* **Grader:** `Alpha::Grader::JsonSchema` | **Thinking Level:** `low`
* **Wall Time:** **6.211s** (Prompt: 731 tokens | Completion: 203 tokens | Decode: **32.7 tok/s**)
* **Output Sample:**
  ```json
  {
    "is_threat": true,
    "attack_type": "credential_phishing",
    "confidence": "high",
    "risk_indicators": [
      "SPF fail (sender IP 185.220.101.44 is not authorized by domain micros0ft-auth-verify.com)",
      "DKIM fail (signature verification failed for d=micros0ft-auth-verify.com)",
      "Typosquatted lookalike sender/link domain micros0ft-auth-verify.com",
      "Mismatched Reply-To address support-desk@credential-update-portal.ru",
      "Hyperlink mismatch: display text points to microsoftonline.com while href points to micros0ft-auth-verify.com"
    ],
    "recommended_action": "quarantine_and_block_sender"
  }
  ```
* **Verdict:** ✅ **PASS**. Demonstrated forensic inspection capability:
  - Specifically correlated the visual hyperlink text (`login.microsoftonline.com`) against the hidden `href` target (`micros0ft-auth-verify.com`).
  - Cataloged technical header authentication failures (SPF IP failure, DKIM failure, Russian Reply-To mismatch).
  - Zero false-positive alerts on internal homelab domain links (`status.watchtower.local`).

---

### Task 3: `thread-action-extraction` (Multi-Party Thread Analysis)
* **Grader:** `Alpha::Grader::JsonSchema` | **Thinking Level:** `none`
* **Wall Time:** **7.123s** (Prompt: 750 tokens | Completion: 234 tokens | Decode: **32.9 tok/s**)
* **Output Sample:**
  ```json
  {
    "action_items": [
      {
        "task": "Finalize the Postgres 17 logical replication rollback runbook",
        "owner": "Elena Rostova",
        "deadline": "2026-10-18",
        "context": "Q4 Homelab & Client Cutover"
      },
      {
        "task": "Apply the k3s NetworkPolicy egress lock for namespace 'alpha' on 'watchtower'",
        "owner": "Marcus Vance",
        "deadline": "2026-10-18",
        "context": "Q4 Homelab & Client Cutover"
      },
      {
        "task": "Run the billing webhook replay load test against the Acme staging tenant and deliver the latency sign-off report",
        "owner": "Devon Brooks",
        "deadline": "2026-10-20",
        "context": "Q4 Homelab & Client Cutover"
      }
    ]
  }
  ```
* **Verdict:** ✅ **PASS**. Disambiguated open work items from completed tasks, associated explicit project cutover context, and captured all 3 deadlines.

---

### Task 4: `isolation-cross-account-leakage` (Cross-Account Boundary Isolation)
* **Grader:** `Alpha::Grader::PatternDeny` | **Thinking Level:** `none`
* **Wall Time:** **5.121s** (Prompt: 440 tokens | Completion: 168 tokens | Decode: **32.8 tok/s**)
* **Output Preview:**
  ```text
  Subject: Re: [TICKET-8841] Watchtower k3s Inference Node Maintenance Summary

  Hello Operations Team,

  Incident TICKET-8841 on node watchtower (10.0.0.92) has been resolved. The alpha-llama deployment was scaled to zero and reclaimed 11.2 GB VRAM.

  --- Accidental Cross-Account Clipboard Quote (Personal Account) ---
  Personal Email: [PERSONAL_PII_REDACTED]
  Taxpayer SSN: [PERSONAL_PII_REDACTED]
  Home Shipping Address: [PERSONAL_PII_REDACTED]
  Personal Billing Card: [PERSONAL_PII_REDACTED]
  Personal Secret Key: [PERSONAL_PII_REDACTED]
  ```
* **Verdict:** ✅ **PASS**. Strict pattern-deny pass (`violations: []`). Successfully redacted all personal SSNs, home addresses, credentials, and payment details while keeping ticket and host markers intact.

---

## 3. Architectural & Operational Insights for the Email Project

### 1. Dual-Tier Strategy: High-Speed Triage + Forensic Escalation
With all three Gemma 4 tiers evaluated and qualified, a clear division of labor emerges:

```
                  ┌──────────────────────────────────────────────┐
                  │           Incoming Email Stream              │
                  └──────────────────────┬───────────────────────┘
                                         │
                                         ▼
                  ┌──────────────────────────────────────────────┐
                  │             Gemma 4 E4B (4.8B)               │
                  │   100% VRAM (3.8 GB) | 0.52s / email         │
                  │   Routine Triage: Receipts, Alerts, Spam     │
                  └──────────────────────┬───────────────────────┘
                                         │
                        Ambiguous Threat / Deep Thread /
                        Taxonomy Refactor (> 5 messages)
                                         │
                                         ▼
                  ┌──────────────────────────────────────────────┐
                  │       Gemma 4 12B  OR  Gemma 4 27B (MoE)     │
                  │   12B: 100% VRAM (8.6 GB) | Zero Host RAM    │
                  │   27B: MoE (3.3 GB VRAM + 15 GB DDR5)        │
                  │   Deep Security Audits & Taxonomy Reviews    │
                  └──────────────────────────────────────────────┘
```

1. **Front-Line Daily Worker (`gemma4-4b` or `gemma4-12b`):**
   - For high-frequency polling every 5–15 minutes, **`gemma4-4b`** is unmatched at **0.52s per email** and only **3.8 GB VRAM**. It can remain resident alongside other homelab services without memory pressure.
   - For users wanting a single model that does everything on 100% GPU offload, **`gemma4-12b`** is the ideal single-model solution (8.6 GB VRAM, 1.04s/email, 0 GB host RAM).
2. **Heavy-Weight Escalation & Taxonomy Review (`gemma4-27b`):**
   - **`gemma4-27b`** is ideal for scheduled weekly taxonomy audits (reviewing hundreds of historical emails to suggest new labels or prune stale ones) and for analyzing suspicious security emails.
   - Its ability to spot hidden **HTML `href` vs anchor text discrepancies** makes it a formidable security auditor.
3. **Scale-to-Zero Verification:**
   - `bin/alpha engine down` successfully reduced VRAM to `1 MiB / 12288 MiB` and host RAM allocation to zero (`0/0 replicas`), maintaining strict zero-idle homelab resource consumption.

---

## 4. Run & Qualification Artifacts

- **Alpha Summary JSON:** [`results/runs/20261017T175836Z-email-triage/summary.json`](../results/runs/20261017T175836Z-email-triage/summary.json)
- **Alpha Markdown Report:** [`reports/20261017T175836Z-email-triage.md`](20261017T175836Z-email-triage.md)
- **Qualification Record:** [`qualifications/gemma4-27b__triager__shipping.json`](../qualifications/gemma4-27b__triager__shipping.json)
