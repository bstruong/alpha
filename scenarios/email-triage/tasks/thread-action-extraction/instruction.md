Analyze the 6-message multi-party email thread below and extract ONLY the **pending (unresolved)** action items into a single JSON object.

The JSON object must strictly adhere to this schema:
```json
{
  "action_items": [
    {
      "task": "<specific pending action>",
      "owner": "<assigned person>",
      "deadline": "<YYYY-MM-DD or explicit deadline>",
      "context": "<account/project context>"
    }
  ]
}
```

Do NOT include any task that is explicitly confirmed as already completed in later replies (specifically, do NOT include rotating the staging TLS certificate).

### Multi-Party Email Thread (`Subject: Re: Q4 Homelab & Client Cutover Checklist`)

**[Message 1 — From: Elena Rostova <elena@apex-consulting.io> | Date: 2026-10-16 09:10 UTC]**
Team, before Monday's cutover we need to track these items:
1. Rotate the staging TLS certificate on the edge proxy.
2. I (Elena Rostova) will finalize the Postgres 17 logical replication rollback runbook by `2026-10-18`.

**[Message 2 — From: Brian <alex@apex-consulting.example> | Date: 2026-10-16 09:42 UTC]**
Update on item #1: I already rotated and verified the staging TLS certificate this morning. That item is 100% done and closed—remove it from the open action list.

**[Message 3 — From: Marcus Vance <marcus@example.local> | Date: 2026-10-16 10:15 UTC]**
Got it. On the homelab side, I (Marcus Vance) will apply the k3s NetworkPolicy egress lock for namespace `alpha` on `watchtower` by `2026-10-18`.

**[Message 4 — From: Devon Brooks <devon@apex-consulting.io> | Date: 2026-10-16 11:05 UTC]**
We also need someone to run the billing webhook replay load test against the Acme staging tenant and send the latency sign-off. Should I take that for Tuesday?

**[Message 5 — From: Elena Rostova <elena@apex-consulting.io> | Date: 2026-10-16 11:20 UTC]**
Yes please, Devon. Assigning Devon Brooks to run the billing webhook replay load test and deliver the latency sign-off report by `2026-10-20`.

**[Message 6 — From: Marcus Vance <marcus@example.local> | Date: 2026-10-16 11:45 UTC]**
Confirmed: staging TLS is already closed, and our three open actions are with Elena (`2026-10-18`), Marcus (`2026-10-18`), and Devon (`2026-10-20`).
