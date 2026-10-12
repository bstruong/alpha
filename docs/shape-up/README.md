# Shape Up: Project Alpha & Project Omega

Sovereign AI pair on the homelab Tailscale mesh.

| System | Role | Origin |
|--------|------|--------|
| **Alpha** | Headless evaluation & benchmarking harness | Repurposed `berserker` |
| **Omega** | Agent control plane & mobile cockpit | Greenfield Rails 8 + Hotwire Native |

## Documents

1. [`01-alpha-transition.md`](01-alpha-transition.md) — `berserker` → Alpha audit, domain model, sandbox, report schema
2. [`02-omega-pitch.md`](02-omega-pitch.md) — 2-week Shape Up pitch for the iOS Hotwire Native MVP
3. [`03-alpha-omega-contract.md`](03-alpha-omega-contract.md) — Qualification handoff and failure→fixture extraction

## Shared constraints

- Inference stays on local nodes (llama-server / vLLM / Ollama); zero PII egress for coding sessions that touch private repos.
- Pi coding agent (`@earendil-works/pi-coding-agent`) is the executor under Omega; Alpha may invoke the same binary headlessly for graded trials.
- Shape Up: fixed 2-week appetite, variable scope, explicit no-gos, thin vertical slices.
