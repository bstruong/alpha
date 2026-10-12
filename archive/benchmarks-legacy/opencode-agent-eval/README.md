# OpenCode Local-Model Agentic-Edit Investigation — Summary (2026-07-23/24)

## Question
Can a local Ollama model do reliable agentic *edits* in OpenCode (build agent) on the Odysseus repo?

## Verdict
- **≤14B models: no.** Every one fails somewhere in the chain (tool-call format, arg-filling, or code competence).
- **32B native-tool-caller (qwen3:32b): mostly — 2/3.** First real competence. Justifies a VRAM upgrade, but not cloud-grade (still review edits).

## Failure modes found (per model)
| Model | Result | Failure |
|---|---|---|
| qwen2.5-coder 7b/14b/32b | 0/3 | text-emits tool calls (no `<tool_call>` tags) → not parsed. Family trait at ALL sizes. |
| llama3.1:8b | ruled out | can't emit edit-style tool calls (0/3) |
| mistral-nemo:12b | 0/3 | valid tool format, but invalid args (empty oldString / missing content) + loops |
| qwen3:8b | 0/3 | native tool_calls OK, but reasoning-stall OR destroyed the function (SyntaxError) |
| **qwen3:32b** | **2/3** | tB ✅, tA ✅, tC ❌ (correct algorithm, wrong indentation → module-level `return`) |

## The tool-call format fix (software, backend-agnostic)
qwen2.5-coder won't emit `<tool_call>` tags; it emits bare JSON. Fix = custom Modelfile overriding
TEMPLATE so `.ToolCalls` renders bare JSON (matches the model). See `Modelfile.q25tools{,.14b,.32b}`.
Restores native tool_calls, BUT the family still fences (```json) / botches quote-escaping in
OpenCode's real context, so unreliable regardless. Not worth using; documented for reference.

## GPU upgrade decision
- Hardware: RTX 3060 12GB (caps at ~14B; NVIDIA off the table going forward per Brian).
- Options: Intel Arc Pro B60 (24GB) / **B70 (32GB, preferred)** via **IPEX-LLM Ollama fork** (not mainline).
- Why B70: fits 32B at higher quant (q6/q8, may fix indentation-type slips) + KV-cache headroom.
- Caveats: (1) re-verify tool-call parity on IPEX-LLM after buying; (2) run a qwen3:32b-class native
  tool-caller, NOT qwen-coder; (3) 2/3 = usable-not-perfect, review edits.
- Speed note: today's ~18min/task is pure CPU-offload penalty (10 of 25GB in VRAM, GPU 22% util).
  Fitting the whole model in VRAM → seconds-to-low-minutes.

## INCIDENT: monitor dropped to 640x480
Cause: 32B filled ~10 of 12GB VRAM on the SAME 3060 that drives the display (DP-6 / card2) →
kwin/Wayland fell back to 640x480 and lost the EDID mode list. NO settings changed; VRAM freed after.
Fix: log out/in OR replug the DisplayPort cable (forces EDID re-read). sysfs `detect` was nvidia-ignored;
kwin refuses to disable the sole output. FOLLOW-UP TODO: ~~add Ollama VRAM guardrail so a big model can't
crowd the display GPU again~~ — DONE, see "VRAM GUARDRAIL" section below (2026-07-24).

## VRAM GUARDRAIL (resolved 2026-07-24)
Goal: stop a large model from crowding the RTX 3060's VRAM enough to repeat the 640x480 incident above.

Config: `/etc/systemd/system/ollama.service.d/override.conf`
```
Environment="OLLAMA_GPU_OVERHEAD=3221225472"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_KEEP_ALIVE=2m"
Environment="LLAMA_ARG_FIT_TARGET=4096"
```
Apply with `sudo systemctl daemon-reload && sudo systemctl restart ollama` after editing.

**Gotcha (the important part):** `OLLAMA_GPU_OVERHEAD` alone did *not* fix it. It only feeds
Ollama's Go-level scheduler (`sched.go`, decides if/where a model can run at all) — it does NOT
constrain llama.cpp's actual layer-fit algorithm (`common_params_fit_impl`), which has its own
free-memory margin defaulting to 1024 MiB regardless of `OLLAMA_GPU_OVERHEAD`. With only the
overhead var set, qwen3:32b still landed at 10.8/12GB VRAM used (~1.5GB free) — barely better than
the incident itself.

The real knob is **`LLAMA_ARG_FIT_TARGET`** (MiB) — it sets the free-VRAM margin llama.cpp's fit
step targets when deciding how many layers to put on GPU vs CPU. Setting it to 4096 dropped usage
to 7.7/12GB (~4.5GB free) and cut GPU layers from 27/65 to 18/65 for the same qwen3:32b load.
Verified via `journalctl -u ollama`, look for `common_params_fit_impl: ... target=N MiB` and
`offloaded X/65 layers to GPU`, cross-checked against `nvidia-smi --query-gpu=memory.used`.

Trade-off: fewer GPU layers = slower inference (more CPU offload). Acceptable given the alternative
is losing the display again. `OLLAMA_MAX_LOADED_MODELS=1` and `KEEP_ALIVE=2m` are supplementary
(prevent concurrent model stacking; shrink the idle-loaded window) — neither was the load-bearing fix.

## Config state (~/.config/opencode/opencode.json)
build agent pinned to qwen2.5-coder:7b; permission.edit=ask (write=noop, edit covers write/patch);
provider.models lists only installed models (qwen3:8b, qwen2.5-coder:7b, qwen3:32b).

## Models on machine (post-cleanup)
KEEP: qwen2.5-coder:7b (app sessions/endpoints), llama3.1:8b (app endpoint), qwen3:8b (research),
qwen3:32b (validation / post-upgrade). Deleted: mistral-nemo, qwen2.5-coder 14b/32b, all -tools:* .

## Files here
Modelfile.q25tools* (fix), task{B,C}_before.patch (regression setups), *.sh (harnesses),
ab-results/ + results_32b_patched/ + results_qwen3_32b/ (per-task diffs, logs, test outputs).
Full findings also in ~/.claude/projects/-home-brian-odysseus/memory/opencode-build-agent-model.md
