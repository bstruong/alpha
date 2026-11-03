# Infrastructure Topology

Canonical roles for running Alpha (and optionally Omega). Adapt hostnames and hardware to your environment.

---

## Roles

| Role | Purpose |
|------|---------|
| **Inference host** | GPU (or CPU) machine running an OpenAI-compatible server (e.g. llama-server). Alpha is an HTTP client; it does not own model weights. |
| **Eval host** | Where `bin/alpha run` / sandboxes execute. Often the same machine as inference, or a networked client pointed at `OPENAI_BASE_URL`. |
| **Operator workstation** | Day-to-day development and Tailscale/SSH access. Not required to run benchmarks. |
| **Cloud / CI agents** | Optional for developing harness code and opening PRs. Do not treat cloud disks as the model test bed unless you intentionally wire inference there. |

---

## Workflow

```
Develop harness (local or CI)  →  Deploy to eval host  →  Wake inference  →  alpha run / qualify
```

1. Develop harness and scenario code locally or in CI.
2. Point `OPENAI_BASE_URL` at your inference server.
3. Run scenarios, publish qualifications, and (optionally) import them into Omega.

---

## Naming in code & configs

| Legacy string | Means |
|---------------|--------|
| `Workstation`, `workstation.env`, `node_class: workstation-32g-3060` | Historical name for a 32 GB / RTX 3060-class inference lab host |
| Prefer going forward | Env-based paths; `node_class` values that describe resources, not private hostnames |

---

## Related docs

- [`engine/README.md`](../engine/README.md) — local llama-server helpers and `models.ini`
- [`docs/workstation-ai-stack.md`](workstation-ai-stack.md) — stack diagram
- [`docs/shape-up/`](shape-up/) — Alpha / Omega Shape Up pitches

## Alpha software pins

| Tool | Pin |
|------|-----|
| Ruby | 4.0.7 (`.ruby-version`, `.mise.toml`) |
| Rails (scenario apps) | ~> 8.1.4 where applicable |
