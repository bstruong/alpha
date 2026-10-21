Perform a security and phishing audit on the raw email message below received by `alex@apex-consulting.example`.
Inspect the SMTP authentication headers (`SPF`, `DKIM`, `DMARC`), sender display name vs. envelope domain, `Reply-To` header, and embedded hyperlinks.

Output a single JSON object adhering strictly to this schema:
- `"is_threat"`: `true` or `false` (boolean)
- `"attack_type"`: `"credential_phishing"`
- `"confidence"`: `"high"` (or numeric `0.98`)
- `"risk_indicators"`: Non-empty array of strings listing the specific technical indicators detected (must explicitly mention the `SPF` fail, `DKIM` fail, the typosquatted lookalike sender/link domain `micros0ft-auth-verify.com`, and the mismatched `Reply-To` address `support-desk@credential-update-portal.ru`).
- `"recommended_action"`: Specific remediation action (e.g., `"quarantine_and_block_sender"`)

Note: The internal homelab status link `https://status.example.local` appended by the local gateway footer is a known benign internal URL and must NOT be flagged as malicious.

### Raw Email Under Audit

```http
Delivered-To: alex@apex-consulting.example
Received: from mail-relay99.external-bulk.net (185.220.101.44) by mx.apex-consulting.io
Authentication-Results: mx.apex-consulting.io;
  spf=fail (sender IP 185.220.101.44 is not authorized by domain micros0ft-auth-verify.com);
  dkim=fail (signature verification failed for d=micros0ft-auth-verify.com);
  dmarc=fail (p=quarantine dis=none) header.from=micros0ft-auth-verify.com
From: "Microsoft 365 Security Team" <security-alert@micros0ft-auth-verify.com>
Reply-To: support-desk@credential-update-portal.ru
To: alex@apex-consulting.example
Subject: [URGENT] Immediate MFA Token Re-Authentication Required Within 2 Hours
Content-Type: text/html; charset="UTF-8"

<html>
<body>
<p>Dear Brian,</p>
<p>We detected anomalous sign-in activity on your corporate Microsoft 365 tenant. Your account will be suspended in 2 hours unless you re-verify your credentials and MFA seed immediately:</p>
<p><a href="http://login.micros0ft-auth-verify.com/oauth2/v2.0/authorize?mode=credential_harvest">https://login.microsoftonline.com/common/oauth2/authorize</a></p>
<hr>
<small>Local Gateway Notice: Checked by Watchtower Mail Guard (https://status.example.local)</small>
</body>
</html>
```
