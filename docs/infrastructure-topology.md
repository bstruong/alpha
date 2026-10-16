# Infrastructure Topology

Canonical roles for the machines involved in Project Alpha / Project Omega.
Older docs may say “Workstation” — that name means the **AM5 homelab node** below, not the Haswell desk machine.

---

## Machines

| Name | Hardware (summary) | OS (target) | Role |
|------|--------------------|-------------|------|
| **AM5 homelab** | AMD Ryzen 7 9700X, RTX 3060 12 GB, 32 GB DDR5-6000, Samsung 990 Pro NVMe | **Fedora Server** | **Production and staging/test.** Local inference (`llama-server` / vLLM / Ollama), Alpha graded benchmarks, Omega-supervised Pi sessions. On the Tailscale mesh. |
| **Haswell workstation** | Intel Haswell-era desk machine (operator seat) | Operator’s local OS | **Not** an Alpha/Omega eval or staging host. Used for browsing, Tailscale access, and light operator tasks. Does not run model benchmarks or staging deployments. |
| **Cursor cloud agents** | Managed cloud VMs | Cursor environment | **Primary software development** for Alpha/Omega (design, implementation, PRs). Do not treat cloud agent disks as the model test bed. |

Historical notes in `reports/` may still say “Arch Linux LTS” or label the AM5 box only as “Workstation.” Treat those as point-in-time lab notes; **this file wins** for current topology and OS target.

---

## Workflow

```
Cursor cloud agents          Haswell desk              AM5 homelab (Fedora Server)
(develop Alpha/Omega)   →    (operator / Tailscale) →  prod + staging/test
     code & PRs                                         • engine / inference
                                                        • alpha run (evals)
                                                        • Omega Pi sessions
```

1. **Develop** harness and cockpit code with Cursor cloud agents (and frontier planners for specs).
2. **Deploy / pull** to the AM5 homelab over Tailscale.
3. **Stage and produce** on AM5: start inference → run Alpha scenarios → publish qualifications → Omega only defaults to Alpha-qualified presets.
4. **Haswell** is never the `InferenceTarget` and never the Alpha sandbox host.

---

## Naming in code & configs

| Legacy string | Means |
|---------------|--------|
| `Workstation`, `workstation.env`, `node_class: workstation-32g-3060` | AM5 homelab |
| Prefer going forward | `am5-homelab`, `node_class: lab-gpu-32g` |

The Haswell desk machine must not appear as an Alpha `InferenceTarget` or Omega `Node` with role `workstation|lab` unless explicitly added later for a non-eval purpose (not planned).

---

## Related docs

- [`engine/README.md`](../engine/README.md) — AM5 engine profile and Fedora Server target
- [`docs/workstation-ai-stack.md`](workstation-ai-stack.md) — stack diagram (AM5 = local execution)
- [`docs/shape-up/`](shape-up/) — Alpha / Omega Shape Up pitches
- `hyperbolic-time-chamber/ruby-rails/` — Parallel Ruby 4.0.7 / Rails 8.1.4 hand-coding drill lane (migrated out of Alpha)

## Alpha software pins

| Tool | Pin |
|------|-----|
| Ruby | 4.0.7 (`.ruby-version`, `.mise.toml`) |
| Rails | ~> 8.1.4 (API mode) |
