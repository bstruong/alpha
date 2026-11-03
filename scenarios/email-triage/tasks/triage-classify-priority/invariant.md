### Triage Output Invariants
- Output ONLY a valid JSON object with no markdown prose or commentary outside the JSON.
- `"urgency"` must be `"P1"` and `"action_required"` must be boolean `true`.
- `"account"` must identify the homelab alert account (`"homelab-alerts@example.local"`).
- `"category"` must be `"production_alert"`.
