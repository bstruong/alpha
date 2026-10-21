### Security Audit Invariants
- Output ONLY a valid JSON object matching `{ is_threat, attack_type, confidence, risk_indicators, recommended_action }`.
- `"is_threat"` must be boolean `true` and `"attack_type"` must be `"credential_phishing"`.
- `"risk_indicators"` must include `SPF` failure, `DKIM` failure, the lookalike domain `micros0ft-auth-verify.com`, and the suspicious `Reply-To` `credential-update-portal.ru`.
- Do NOT flag the benign internal gateway URL `status.watchtower.local` as a malicious indicator.
