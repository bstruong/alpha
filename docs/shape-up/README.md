# Shape Up: Project Alpha & Project Omega

Sovereign AI pair on the Tailscale mesh. **Where things run:** see [`../infrastructure-topology.md`](../infrastructure-topology.md).

| System | Role | Origin |
|--------|------|--------|
| **Alpha** | Headless evaluation & benchmarking harness | Repurposed `berserker` |
| **Omega** | Agent control plane & mobile cockpit | Greenfield Rails 8 + Hotwire Native |

| Environment | Role |
|-------------|------|
| **AM5 homelab** (9700X + 3060, Fedora Server) | Production **and** staging/test — inference, Alpha runs, Omega Pi |
| **Haswell desk** | Operator seat only — not an eval/staging host |
| **Cursor cloud agents** | Primary Alpha/Omega software development |

## Documents

1. [`01-alpha-transition.md`](01-alpha-transition.md) — `berserker` → Alpha audit, domain model, sandbox, report schema
2. [`02-omega-pitch.md`](02-omega-pitch.md) — 2-week Shape Up pitch for the iOS Hotwire Native MVP
3. [`03-alpha-omega-contract.md`](03-alpha-omega-contract.md) — Qualification handoff and failure→fixture extraction

## Shared constraints

- Inference and graded evals run on the **AM5 homelab** (llama-server / vLLM / Ollama); zero PII egress for coding sessions that touch private repos.
- Do not target the Haswell desk machine as an `InferenceTarget` or Alpha sandbox.
- Pi coding agent (`@earendil-works/pi-coding-agent`) is the executor under Omega on AM5; Alpha may invoke the same binary headlessly for graded trials.
- Shape Up: fixed 2-week appetite, variable scope, explicit no-gos, thin vertical slices.
