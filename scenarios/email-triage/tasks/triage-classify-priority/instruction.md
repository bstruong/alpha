You are triaging a multi-account inbox batch across three accounts (`personal`, `work`, and `homelab`).
Review the four incoming emails below, rank their urgency from `P1` (critical infrastructure/production outage) to `P4` (spam/promotional), and output a single JSON object representing the triage classification for the **highest-urgency (`P1`) email only**.

The JSON object must strictly adhere to this schema:
- `"account"`: `"homelab-alerts@watchtower.local"`
- `"category"`: `"production_alert"`
- `"urgency"`: `"P1"` (one of `"P1"`, `"P2"`, `"P3"`, `"P4"`)
- `"action_required"`: `true` (boolean)
- `"summary"`: Concise one-sentence summary of the critical incident on `watchtower`
- `"tags"`: Non-empty array of lowercase string tags (e.g. `["watchtower", "k3s", "nvme", "gpu"]`)

### Incoming Multi-Account Batch

**[Email 1 — Account: `personal` (`alex.personal@example.com`)]**
From: Deals Weekly <promo@ergokeyboards-direct.example>
Subject: FLASH SALE: 40% Off Split Mechanical Keyboards Ends Tonight!
Body: Upgrade your desk setup today with coupon code MECH40. Unsubscribe anytime.

**[Email 2 — Account: `work` (`alex@apex-consulting.example`)]**
From: CloudBilling <billing@saas-metrics.example>
Subject: Invoice #INV-2026-1042 for October 2026 ($49.00)
Body: Your monthly subscription invoice for $49.00 has been generated. Auto-pay is scheduled for November 15, 2026. No immediate action is required.

**[Email 3 — Account: `work` (`alex@apex-consulting.example`)]**
From: Sarah Jenkins <s.jenkins@acmecorp.example>
Subject: Urgent Calendar Conflict: Q4 Architecture Review Tomorrow
Body: Hi Alex, our VP has a hard conflict with tomorrow's 10:00 AM PT Q4 Architecture Review. Can we move the session to 2:00 PM PT tomorrow? Please confirm today.

**[Email 4 — Account: `homelab-alerts@watchtower.local`]**
From: Alertmanager <alertmanager@watchtower.local>
Subject: [FIRING:1] NodeStorageAndGPUCritical on watchtower (10.0.0.92)
Body: CRITICAL P1 PRODUCTION ALERT: k3s node `watchtower` (10.0.0.92) NVMe pool `/mnt/models` is at 98.4% capacity and RTX 3060 GPU reported a PCIe bus reset causing `alpha-llama` deployment crash-loop. Immediate intervention required.
