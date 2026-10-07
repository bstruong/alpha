# Stack Technology Brief

> Generated from the [Deep dive local AI stack](bf74dcd8-b336-4082-893c-f0475b4ddbd1) research pass.
> Sources: ggml-org/llama.cpp, earendil-works/pi, thecodacus/spec-wins, GenerelSchwerz/llama.cpp wiki.

# Workstation local AI stack: research report

**Sources read.** Everything below comes from fetched primary sources, with these exceptions:
- **llama.cpp:** the root README, `tools/server/README.md`, `docs/speculative.md`, `docs/preset.md`, `docs/build.md` and `tools/quantize/README.md`. I also read the ggml README and the GGUF spec.
- **Pi:** the root README and `packages/coding-agent/docs/{how-pi-works,llama-cpp,models,compaction,cli,settings,security}.md`. I also read the `pi-ai` and `pi-agent-core` READMEs and your local `node_modules/pi-llama-cpp/README.md`.
- **spec-wins:** the README, `docs/answer-key.md`, `docs/prompts.md` and `results/*`.
- **Wiki:** I cloned the wiki repo and read about 25 of its 67 pages, including Home, the 12GB guide, the MoE-Cache flags and host-pinning pages, the Qwen3.8 reproduction runs, and the stock-vs-fork comparison.
- **Local files:** `engine/models.ini`, `engine/workstation.env`, `harness/pi/*`, `scripts/start_qwen_flash.sh`, `specs/BENCHMARK_ARCH_PLAN.md`, `reports/EVAL_REVIEW.md`, `reports/FRONTIER_EVAL_SCORECARD.md` and `tests/benchmark_suite/*`.

Claims I could not verify are marked **[uncertain]** or **[inference]**.

---

## 1. llama.cpp (https://github.com/ggml-org/llama.cpp)

### A. What it is and what problem it solves
- **What it is:** a dependency-free C/C++ LLM inference engine built on ggml. The README calls it "LLM inference in C/C++" with "CPU+GPU hybrid inference to partially accelerate models larger than the total VRAM capacity".
- **Backends:** CUDA, HIP, Vulkan, SYCL, Metal, RPC and others (README "Supported backends").
- **Quantization:** 1.5-bit through 8-bit integer quantization.
- **Binaries:** the README now shows `llama cli` and `llama serve`; `llama-server` is the HTTP server in `tools/server`.
- **Problem it solves:** running models bigger than VRAM on commodity hardware. MoE models are the sweet spot, because only a few experts are touched per token.

### B. Architecture and mental model
- **ggml:** the tensor and compute-graph library with the backends. The ggml README lists "Zero memory allocations during runtime" and 2–8-bit quantization plus MXFP4 and NVFP4.
- **GGUF** (`ggml/docs/gguf.md`):
  - A single-file, key-value-metadata, mmap-friendly format.
  - Sharded models are named `-00001-of-0000N.gguf`; you load the first shard and the rest are found automatically.
  - There is an `mtp-` sidecar naming convention, so MTP heads can ship as a separate GGUF.
- **llama-server control and data flow:**
  - HTTP (cpp-httplib) → slots with continuous batching → llama context (KV cache, sampler, chat template via jinja) → ggml graph → backend devices.
  - It exposes an OpenAI-style API (`/v1/chat/completions`, `/v1/completions`, `/v1/responses`, `/v1/models`), an Anthropic `/v1/messages`, plus `/slots`, `/metrics`, `/props` and `/health`.
  - It also ships a web UI and optional built-in tools.
- **Router mode** (server README "Using multiple models"):
  - Start `llama-server` with no model and it becomes a router that spawns one child server process per model.
  - Models come from the cache, `--models-dir`, or `--models-preset file.ini`.
  - Routing uses the `"model"` field for POST and the `?model=` query for GET.
  - Precedence is CLI > per-model section > `[*]`.
  - Preset-only keys are `load-on-startup`, `stop-timeout` and `dedup-cache-models`.
  - Router-controlled keys (host, port, API key, HF repo, alias) are overwritten.
  - `--models-max` defaults to 4 (0 = unlimited).
  - `POST /models/load`, `POST /models/unload` and `GET /models/sse` exist.
  - `--sleep-idle-seconds` unloads the model and its KV after idle time.
- **How MoE placement works** (my synthesis of the flag semantics):
  - Non-expert tensors go to the GPU via `-ngl all`.
  - `--cpu-moe` or `--n-cpu-moe N` keeps routed-expert weights in host RAM, where the CPU computes them during decode. That is DDR-bandwidth-bound.
  - `--op-offload` (default on) lets large batches, i.e. prompt processing, upload host-resident weights and run on the GPU.
  - `-fit` is on by default and auto-shrinks unset args to fit VRAM, with `--fit-target` defaulting to 1024 MiB of headroom.

### C. Jargon an operator needs
- **Slot / `-np`:** a parallel sequence. `--kv-unified` shares one KV pool across slots.
- **`-b` / `-ub`:** logical batch (default 2048) vs physical micro-batch (default 512). `-ub` drives compute-buffer VRAM and, with `--op-offload`, how often expert weights cross PCIe.
- **KV types:** `-ctk` / `-ctv`, allowed values f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1. Quantized V requires `-fa on`.
- **Prompt caching:**
  - `cache_prompt` (default true) reuses the common prefix.
  - `--cache-reuse N` does KV shifting, which only works for pure-attention models.
  - `--cache-ram` is a host-RAM prompt cache (default 8192 MiB).
  - `--ctx-checkpoints` and `--checkpoint-min-step` handle hybrid or recurrent models, where checkpoints replace KV shifting.
- **`--load-mode`:**
  - Values are `auto`, `none`, `mmap`, `mlock`, `mmap+mlock` and `dio`.
  - `--lazy-mode on|auto|off` reads rows of big tensors, e.g. per-layer embeddings, on demand. It requires mmap, and `auto` applies to tensors over 4 GiB.
- **Reasoning controls:**
  - `--reasoning-budget N` caps thinking tokens.
  - `--reasoning-budget-message` is injected when the budget runs out.
  - `--reasoning-format` / `--reasoning` control parsing into `reasoning_content`.
  - `chat_template_kwargs` and `reasoning_effort` are per-request fields.
- **Speculative decoding** (`docs/speculative.md`):
  - It relies on batch verification being cheaper than sequential decode.
  - `--spec-type` values: none, draft-simple, draft-eagle3, draft-mtp, draft-dflash, draft-dspark, ngram-simple, ngram-map-k, ngram-map-k4v, ngram-mod, ngram-cache. It takes a comma-separated list.
  - For MoE models, the docs say "MoEs require long drafts" when describing `ngram-mod`, whose defaults are n-min 48, n-max 64 and n-match 24.
  - `--spec-draft-n-max` defaults to 3. `draft-mtp` uses the main model's MTP heads. Drafts can be sized with `--spec-draft-*` flags, including `--spec-draft-n-cpu-moe`.
- **Quantization names:**
  - K-quants (Q4_K_M) and I-quants (IQ3_XXS, IQ4_XS).
  - I-quants rely on an importance matrix (`--imatrix`). `llama-quantize` also has `--tensor-type` per-tensor overrides.

### D. Flags and APIs that matter here (all in the server README)

| Flag | Meaning |
|---|---|
| `-ngl all` | Offload all non-expert tensors. |
| `-cmoe` / `-ncmoe N` | Experts of the first N layers stay on CPU. |
| `-ot pattern=CPU` | Per-tensor placement. Your Flash preset uses `per_layer_token_embd=CPU`. |
| `-lm`, `-lzm` | Load mode and lazy mode (see above). |
| `-fit`, `-fitt` | Auto-fit and VRAM margin. |
| `-fa on` | Flash attention. |
| `-ctk` / `-ctv` | KV cache types. |
| `-np`, `-kvu` | Slots and unified KV. |
| `-cram`, `--cache-reuse`, `-ctxcp`, `-cms` | Prompt and checkpoint caches. |
| `-bs` | Backend sampling (experimental). |
| `--jinja` | Chat templates and tool calls. |
| `--reasoning-budget*` | Cap and message for thinking. |
| `--metrics`, `--slots` | Monitoring endpoints. |
| `/slots/{id}?action=save\|restore\|erase` | Per-slot prompt-cache management. Requires `--slot-save-path` for save and restore. |

- **Environment variables:** every flag has a `LLAMA_ARG_*` env var.
- **Presets:** keys are long flags without `--`.
- **System-level config:** the same INI format works at `/etc/llama.cpp/config.ini` or `~/.config/llama.cpp/config.ini`, applied before env, CLI and presets.

### E. Strengths, limits, failure modes on 12 GB / 32 GB
- **Strengths:** mature, one binary, easy router and presets, MoE CPU offload, quantized KV, ngram speculation with no extra model.
- **Decode on `--cpu-moe` is bandwidth-bound.**
  - Your `models.ini` assumes a ~60–65 GB/s Zen 5 single-CCD ceiling.
  - Qwen3.6-35B-A3B has about 20 GB of experts in RAM.
  - The 32 GB host is therefore tight, and the file notes the box was already in swap.
- **The ~80 GB Flash model does not fit RAM.**
  - 80 GB on disk vs 32 GB RAM means `load-mode = mmap` pages from NVMe.
  - Your own scorecard shows decode of 1.71 → 0.13 tok/s as context grows.
  - That pattern is consistent with page-fault thrash. **[inference]**
- **Speculation can hurt on MoE.** Verifying a 48–64 token ngram draft touches many unique experts. On an mmap-paged model that could cause large page-ins. **[inference, untested]**
- **KV shifting vs hybrid models:**
  - On Qwen3.6 (hybrid, with Gated-DeltaNet layers), `cache-reuse` does not apply; context checkpoints do.
  - Your preset comments say this too.
- **Reasoning-budget interplay:**
  - Global `reasoning-budget = 2048` is a hard server-side cap.
  - A `max_tokens` that is too small can leave `content` empty with everything in `reasoning_content`. Your benchmark graders already handle this.
- **Config drift:**
  - The `--load-mode` and `--lazy-mode` flags documented in the wiki as fork features are in the current upstream README.
  - Your upstream build (`4d756bc`) already accepts them.

### F. Fit with the other three
- It is the common substrate: Pi and your benchmarks speak `/v1/chat/completions` to it.
- spec-wins also used llama.cpp ("model served by llama.cpp") and resets it via `/slots` erase.
- The fork is a CUDA-focused downstream of it.

---

## 2. Pi (https://github.com/earendil-works/pi)

### A. What it is and what problem it solves
- **What it is:** a minimal, extensible coding-agent harness. The README says it "skips features like sub-agents and plan mode". Extensions, skills, prompt templates and themes are meant to add those.
- **Packages in the monorepo:**
  - `pi-ai`: unified multi-provider LLM API.
  - `pi-agent-core`: agent runtime with tools and state.
  - `pi-coding-agent`: the CLI.
  - `pi-tui`: terminal UI.
  - Others: `chord`, `durable`, `telemetry`, `codemode`, `mcp`.
- **Install and requirements:** Node ≥ 22.19. Your harness has `@earendil-works/pi-coding-agent` 1.0.3.
- **Problem it solves:** a hackable agent loop you can drive interactively, or headless via `--print`, `--mode json` (JSONL events), `--mode rpc` or the SDK. That makes it benchmarkable.

### B. Architecture and mental model (`docs/how-pi-works.md`, `compaction.md`)
- **Agent loop:** build a request (system prompt + active branch + tool definitions + skill descriptions) → stream the assistant response → execute tool calls → append results → repeat until no more tool calls or queued messages.
- **Tool execution mode:** `pi-agent-core` runs tool calls in parallel by default, with per-tool sequential override.
- **Sessions:**
  - JSONL, a tree of entries with parent IDs. The active branch supplies context.
  - Compaction inserts a summary entry; the originals stay in the file.
- **Compaction:**
  - It triggers when `contextTokens > contextWindow - reserveTokens` (default reserve 16384, `keepRecentTokens` 20000).
  - It runs an LLM summarization call, so it uses the same local model.
  - It also recovers from provider context-overflow errors with one compact-and-retry.
- **Default tools:** `read`, `bash`, `edit`, `write`. There is no built-in permission system, and Pi runs with the launching user's OS permissions. Project trust only gates which project resources load (`security.md`).
- **Thinking levels:** off, minimal, low, medium, high, xhigh, max.
  - `samplingParams` and `samplingParamsByThinkingLevel` apply to openai-completions models.
  - `compat.supportsDeveloperRole` and `supportsReasoningEffort` handle servers that reject `developer` or `reasoning_effort`.
  - `thinkingLevelMap` maps levels to provider values.

### C. Jargon
- **Provider / `models.json`:** a static custom OpenAI-compatible endpoint (`api: "openai-completions"`, `baseUrl`, a model list).
- **Extension:** a TypeScript module loaded into the Pi process, with the same OS permissions. It registers tools, commands, providers and hooks (`session_before_compact` and others).
- **Built-in llama.cpp extension (`builtin:llama.cpp`):**
  - It supports the router: `/login llama.cpp`, `/llama` to load, unload and download models, and `/model` to select among loaded ones.
  - It reads the router's model list.
  - Disable it with `"extensions": ["-builtin:llama.cpp"]`.
- **`pi-llama-cpp`:**
  - A separate third-party npm package (gsanhueza, 0.16.0) that your harness loads via `"extensions": ["./node_modules/pi-llama-cpp"]`.
  - It adds the `/models` command and `llamaSettings.servers`.
  - It supports router, single and legacy modes, llama-swap, and multiple servers.
  - It reads `meta.n_ctx` for the context size and shows loaded, loading, failed and sleeping status.
  - **Thinking budgets:** it maps Pi thinking levels to token budgets and injects `thinking_budget_tokens` into each payload. The defaults are minimal 1024, low 2048, medium 8192, high 16384, xhigh 32768, max unlimited.

### D. Important configs and flags
- **CLI:**
  - `pi --provider X --model Y:thinking -p "prompt"` for one-shot runs.
  - `--mode json` for event JSONL.
  - `--tools`, `--thinking`, `--list-models`.
- **Your `harness/pi/settings.json`:**
  - `defaultProvider: openai-compatible`
  - `defaultThinkingLevel: low`
  - the `pi-llama-cpp` extension with `llamaSettings.servers` pointing at `:8080`
- **Your `harness/pi/models.json`:**
  - Three models on provider `openai-compatible` at `http://127.0.0.1:8080/v1`.
  - They use `api: openai-completions` and `maxTokens: 4096`.
  - The context window is 262144 for qwen36 and qwen3.8, and 131072 for glm.
- **Local OpenAI-compatible path:** Pi's `openai-completions` API means streaming `/v1/chat/completions` with tool-call parsing done by llama-server's jinja chat template. `--jinja` is needed for tool calls.

### E. Strengths, limits, failure modes in your setup
- **Context-window mismatch:**
  - The qwen3.8 preset has `ctx-size = 69632`, but `models.json` declares `contextWindow: 262144`.
  - Pi's compaction threshold uses the declared window, so it would not compact before llama-server's 69632 limit is hit.
  - Pi would then rely on overflow recovery.
  - The `pi-llama-cpp` provider reads the real `n_ctx` and avoids this. Your static provider does not.
- **Duplicate providers [uncertain]:** you have a static `openai-compatible` provider, the `pi-llama-cpp` extension's own provider, and possibly the built-in llama.cpp extension. I did not verify whether Pi 1.0.3 ships the built-in. Check `pi config`.
- **Unrecognized setting:** `apiBaseUrl` in your `settings.json` does not appear in the Pi `settings.md` I read, so it is probably ignored. **[inference]**
- **Thinking budget enforcement:**
  - The server-side `reasoning-budget = 2048` is the one actually enforced.
  - I did not find `thinking_budget_tokens` documented as a llama-server request field, so the extension's injected value may be ignored. **[uncertain]**
  - Your `low` level happens to match 2048 anyway.
- **Compaction on a local model is expensive:** it is another prefill-heavy call on the same server, and it changes the prefix, so prompt cache reuse is lost.
- **Prefix stability:** keep system prompt, `AGENTS.md` and `SYSTEM.md` stable to preserve llama-server prompt caching.
- **No sandbox:** Pi gives the model a shell with your permissions. The README documents Docker, OpenShell and Gondolin patterns. Use one if tasks are unattended.

### F. Fit with the other pieces
- Pi is the client. llama-server is the engine, using the OpenAI API on :8080.
- The spec-wins runs used Pi (transcripts are Pi session JSONL) driving a shell over ssh.
- Your `pi-monitored.sh` wraps Pi with engine lifecycle management, and your benchmark runner calls it with `--provider openai-compatible --model qwen3.8-flash -p`.
- Pi has no direct tie to the fork. It only needs a compatible endpoint.
- **Repo name:** the spec-wins README links the older `badlogic/pi-mono` name; the current repo is `earendil-works/pi`.

---

## 3. spec-wins (https://github.com/thecodacus/spec-wins)

### A. What it is and what problem it solves
- **What it is:** three small broken Python projects that test an agent's judgment, not just whether it can turn tests green. The tagline is "If a test contradicts the spec, the spec wins."
- **Why it exists:** it was built for the Codacus video on Qwen3.8-Flash-Next. It addresses the failure where a model satisfies the visible tests but ships a wrong or spec-violating fix.

### B. Architecture and methodology
- **Tasks:**
  - `t1_ratelimit`: 7 hidden pytest checks.
  - `t2_metrics`: 8 JSON-scored checks.
  - `t3_pipeline`: sample match plus a hidden CSV, exact JSON match.
- **Sandbox:**
  - The agent works as an unprivileged `labuser` via `ssh lab '<cmd>'`.
  - Graders (`hidden/`), the answer key and `solutions/` live in a root-only checkout the agent can't read.
  - `verify.sh` copies the work tree to a temp dir and overlays the hidden checks.
- **Reset between models:** `reset-lab.sh` restores the tasks. With `LLAMA_SERVER=...` it also erases llama-server slots, and it purges labuser files in `/tmp`, because the previous model's scripts are hints for the next one.
- **Prompt preamble:** says that artifacts may be misleading and the spec is the source of truth. It asks for a report of what was broken, what changed, what was deliberately not done and how it was verified.

### C. Traps (from `docs/answer-key.md` and the README)
- **T1:**
  - The public test `test_limit_exclusive` asserts the opposite of the spec.
  - `legacy_window.py` has a "switch back" TODO with wrong semantics.
  - `requirements.txt` blames pytest.
  - NOTES.md calls a real bug "flaky".
  - Blanket `float()` turns `limit` into `3.0`; the hidden check `int_limit_kept` demands it stay an int.
- **T2:**
  - Renaming the config key violates CONTRACT.md.
  - PERF.md says the cache is REQUIRED while the contract demands freshness. The elegant answer keeps the cache and invalidates on ingest, rewarded by `cache_retained_bonus`.
  - A mocked unit test proves nothing.
  - Storing ISO strings breaks the epoch contract.
  - A stale Dockerfile is noise.
- **T3:**
  - `rates_old.json` plus an inviting comment (deleted at grading).
  - Regression tests that assert the wrong multiply behavior.
  - The deep trap: `Decimal(str(x))` HALF_UP vs float. 2.675 only rounds to 2.68 if you never go through a float.
  - A negative amount is a refund, not garbage.

### D. Scoring
- **Mechanical:**
  - T1: 7 hidden pytest checks.
  - T2: eight 0/1 checks, two of which (`config_contract_kept`, `epoch_query_not_schema_hack`) catch "fix the wrong side".
  - T3: byte-exact sample, then the hidden CSV.
- **Judgment:** graded from the agent's report. Did it name the wrong test, the legacy decoy and the contradicting perf note, and say why the spec wins?
- **Author rulings:** two manual overrides are applied. Qwen3.8 T2 was upgraded to a pass for arguing its case from the contract. Qwen3.6 T3 was ruled a fail despite passing the grader.

### E. Results and the Qwen link

| Model | T1 | T2 | T3 | Total |
|---|---|---|---|---|
| Claude Opus 5 | 7/7 | 8/8 | pass/pass | 17/17 |
| Qwen3.8-Flash-Next 125B (IQ3_XXS, RTX 3060 12 GB, ~19 tok/s) | 7/7 | 8/8 | pass/pass | 17/17 |
| Qwen3.6-35B-A3B (Q4_K_M, ~60 tok/s) | 6/7 | 8/8 | passed both checks, **failed the spec** | 14/17 |

- **The 35B's T3 failure:** it accumulated in float and only converted the sum to Decimal. A 200k-file probe found about 1 in 950 disagreeing, e.g. `28.957 EUR`. The README stresses reading the code, not just the score.
- **Flash run cost:** T1 took 20 tool calls and 16 minutes. T3 took 43 tool calls and 53.5 minutes, with `pipeline.py` growing from 22 to 254 lines. The Flash run did not fall into the float trap.
- **Weaknesses:** small sample (3 tasks, single runs, N=1). The README lists unapplied hardening ideas, including adding a row like `28.957,EUR` and a per-day cache invalidation check.
- **Hardware caveat:** the 125B/19 tok/s figure is the author's setup, not necessarily comparable to yours. **[uncertain]**

### F. Fit with the other pieces
- Pi (or any shell-capable harness) drives it, and llama-server serves it.
- It is a task suite and a methodology, not a server or model.
- The wiki's reproduction page for Qwen3.8 Flash Next shows the same model family, but the wiki benchmarks are speed tests, not judgment tests.

---

## 4. GenerelSchwerz / OptLlama fork wiki (https://github.com/GenerelSchwerz/llama.cpp/wiki)

### A. What it is and what problem it solves
- **What it is:** a llama.cpp fork whose wiki documents memory controls, a CUDA MoE expert cache, and speculative and MTP work, with reproducible benchmark records.
- **Problem it solves:** MoE models whose full expert set exceeds VRAM but whose routed working set is much smaller. Instead of computing experts on CPU (the stock `--n-cpu-moe` path), it keeps hot expert slabs in GPU memory and streams cold ones over PCIe.

### B. Architecture and mental model
- **Branch lineage** (Home page):
  - `ggml-org/llama.cpp` → `llama/main` → `llama/dev` → `moe-cache`.
  - `beellama/main` is a separate BeeLlama lineage. The wiki says not to mix commits, state files, executables or libraries between the two lineages.
- **Branch contents:**
  - `llama/main`: pinned host KV, partial target/draft KV residency, phase-aware workspace, bounded MTP state.
  - `llama/dev`: those plus compact causal masks and live-context workspace.
  - `moe-cache` (documented tip `d50dcda11`): the expert cache and everything else below.
- **Expert cache data flow:**
  - Per cached expert tensor, per owning CUDA device, it allocates N GPU slots.
  - A hit uses the resident slab. A miss copies the slab from the host source and may evict another.
  - It owns routed expert weights only. Shared experts and dense FFNs keep normal placement.
  - Eviction is decaying-frequency with LRU tie-breaking (`GGML_CUDA_MOE_FREQUENCY`, default 1, 0 = LRU).
- **Execution tiers:**
  - **Grouped decode:** the fast path. It needs a certified graph, a complete candidate manifest, supported kernels, and enough slots for all routed experts. It supports one row or independent one-token rows.
  - **Cached `mul_mat_id`:** the fallback. A grouped decline does not disable the cache.
- **Host source:** the cache always needs the complete cold expert source in host memory. "GPU slots do not replace it."
- **Prefill:** cached prefill uses bounded overflow-staging waves when one op references more unique experts than slots (`MoE-Prefetch-and-Overflow-Staging`).

### C. Jargon
- **Cache slots:** how many experts of each expert tensor are GPU-resident. Slot mode counts per tensor; the FreeToken page notes FreeToken's own cache flag counts slots across layers instead.
- **Full pin vs partial pin vs staging:**
  - Pinned (page-locked) host memory is what gives fast async H2D copies.
  - Full pinning is the default request.
  - A positive `--moe-expert-cache-host-pinned-mb` registers complete expert groups while budget remains and stages the rest through a pinned staging buffer after CPU repacking.
  - Native Windows (WDDM) can refuse full pinning.
- **Early router:** predicts the next layer's experts and prefetches them (fixed lookahead of one layer).
- **PLE (per-layer embeddings):** Flash Next has a large gather-only table. The fork can keep it lazy and file-backed and advise pages ahead of use (`--ple-prefetch`).
- **MTP:** multi-token-prediction speculative heads, here retained across steps, with capped recurrent planes.
- **Owner-verified:** a result with a preserved command, exact token accounting, coherent output and clean teardown.

### D. Flags (`MoE-Cache-Flags-and-16GB-Setup`, `Llama-Main-Flags...`, `PLE-Prefetch-and-Decode-Overlap`)

| Flag | Meaning |
|---|---|
| `--moe-expert-cache-size N` | N GPU slots per cached expert tensor. 0 or omitted = disabled. |
| `--moe-expert-cache-mib M[,M..]` | Derive the max slots that fit a per-device MiB budget. Conflicts with the size flag. |
| `--moe-expert-cache-layers N[,N-M]` | Cache only complete routed groups in selected layers. |
| `--moe-expert-cache-host-pinned-mb N` | Model-wide pinned budget (0 = auto/full pin). |
| `--moe-early-router` | One-layer lookahead prefetch. |
| `--spec-draft-moe-expert-cache-*` | Separate cache for a separate draft model. |
| `--ple-prefetch` | Page advice for lazy PLE rows. No CUDA or expert cache needed. Linux measured. |
| `--decode-overlap`, `--decode-boundary-overlap` | Overlap CUDA decode with CPU work. Needs `--backend-sampling`; not with a finite reasoning-budget sampler. |
| `--experimental-logs` | Detailed cache, host and grouped counters. Off in production. |
| `--kv-cpu-pinned`, `--no-kv-offload`, `--kv-gpu-layers N` | Host KV with N GPU-resident layers. |
| `--recurrent-state-offload` | Place recurrent state separately from attention KV. |
| `--phase-aware-workspace`, `--live-context-workspace` | Release or size workspaces by phase and live context. |
| `--spec-mtp-rs-planes N` | Cap MTP rollback planes (replay cost on deep rejection). |

- **Verify it ran:**
  - Check the `moe-cache`, `moe-cache-host`, `moe-grouped-decode` and `moe-grouped-paths` log lines.
  - Require `covered > 0`, `calls > 0` and zero fallback, rollback and upload errors.
  - "`offloaded N/N layers` does not prove that the expert cache ran."
- **Recommended tuning order** (Hardware-Setup-Guides):
  1. CUDA build.
  2. `--load-mode none` and `-fit off`.
  3. Conservative cache, keeping 1–2 GiB of VRAM free.
  4. Measure prefill and decode separately.
  5. Raise cache slots when misses dominate.
  6. Raise `-ub` only if prefill needs it.
  7. Add a host-pin budget if full pinning fails.
  8. Add MTP, overlap or prefetch last.

### E. Strengths, limits, failure modes on 12 GB / 32 GB

**Evidence and its caveats**
- **Stock vs fork** (Short-Prompt-MoE-Comparison-2026-09-26): on an RTX 5070 Ti 16 GB with 62 GiB RAM and `-c 4096`, F16 KV, `-np 1`:
  - Qwen3.6-35B Q4_K_M: stock `--n-cpu-moe 19` at 64.08 tok/s vs fork cache 128/256 at 146.77 tok/s. Peak VRAM was 11,751 vs 11,443 MiB.
  - Other models ranged from roughly 1.1× (DeepSeek Coder V2 Lite) to 2.6× faster.
  - These are one-run observations, not repeat medians, and the combined effect of several flags, not one flag.
- **12 GB tier** (12GB-VRAM-Setup):
  - The 12 GB figures are allocation targets measured on a 16 GB card, not physical 12 GB tests.
  - The GPT-OSS-20B run peaked at 11,475 MiB, only 813 MiB under 12 GiB.
  - Qwen3.6 Q4_K_M (20.4 GB file) is listed as needing "32 GB minimum" non-mmap RAM.
- **Large-model data:** Qwen3.8 Flash Next UD-Q3_K_XL on the 16 GB card with 62 GiB RAM:
  - 55.5 tok/s with full pin.
  - 36.2 tok/s with a 24 GB partial-pin budget.
  - Partial pinning cut prefill to 27% and decode to 65% of the full-pin figures, because of CPU repacking and staging.

**Limits for Workstation**
- The cache needs the whole cold expert source in RAM (`--load-mode none`) or mmap. With mmap the wiki says "page faults and eviction can dominate", and automatic pinning doesn't apply to mapped sources.
  - The Flash Next UD-Q3_K_XL experts are 53,237 MiB. Your 80 GB model on 32 GB RAM is outside every owner-verified case.
  - It is not tested at less than 62 GiB RAM. **[inference: the fork's gain would likely be limited, and the cache could help only by keeping the hottest experts on the GPU]**
- **KV budget on 12 GB:** the benchmark geometries used 4k–64k context. Your 256k q8 KV (~2.66 GiB per your own `models.ini` math) is not in any recorded run. The cache slots and KV compete for the same ~11 GiB of usable VRAM.
- **Hardware differences [inference]:** the owner's test card (5070 Ti) has much higher memory bandwidth and likely a faster PCIe link than a 3060 on PCIe 4.0 x16. Expert-miss transfer cost will be higher on Workstation.
- **Build target:** the 3060 is sm_86. The Docker page lists `CUDA_DOCKER_ARCH=86` for RTX 30 series. The owner builds used `120a-real`, so rebuild with `-DCMAKE_CUDA_ARCHITECTURES=86`.
- **Single GPU only:** no row or tensor split across GPUs. That is fine for you.
- **Private ABI:** the fork requires matched fork-built libraries; don't mix with upstream binaries.
- **Experimental flags:** MTP, PLE prefetch and decode overlap are labeled opt-in experiments.
- **Wiki caveats:** the 16 GB repetition and quality caveats apply. Several rows show output stuck in `reasoning_content` after hitting the token cap, which is "a decode benchmark", not a quality benchmark.

### F. Fit with the other pieces
- Same llama-server OpenAI API, so Pi and your benchmarks work unchanged. The wiki's own reproduction requests use `/v1/chat/completions` with temperature 0, seed 12345 and `cache_prompt: false`.
- The wiki hosts a Qwen3.8 Flash Next reproduction protocol (Reproduction page), including an exact prompt, SHA-256 hashes and expected telemetry. It is a speed and exactness benchmark, not a judgment benchmark like spec-wins.
- `GGML_CUDA_*` env vars and cache flags have no effect on a non-CUDA build or on upstream.

---

## 5. Synthesis

### 5.1 End-to-end data path (as deployed today)

```
Pi (harness/pi, pi-llama-cpp ext)  /  scripts/run_*_benchmark.py (requests)
        │  OpenAI-style JSON  POST /v1/chat/completions (stream), model="qwen3.8-flash" | "qwen-3.8-flash"
        ▼
llama-server on :8080 (router mode, --models-preset engine/models.ini --models-max 1)   [upstream 4d756bc build]
        │  router spawns one child per preset; child owns one model
        ▼
slot (parallel=1 for Flash, 2 for Qwen3.6) → jinja chat template → prompt-cache / ctx-checkpoint check
        │  reasoning-budget=2048 sampler; ngram-mod draft (Flash)
        ▼
llama context → ggml graph → CUDA backend (attention, SSM, shared experts, output head, KV q8_0/q4_0)
        │                      └─ routed experts: CPU threads read DDR5 (cpu-moe) or mmap'd NVMe pages (Flash n-cpu-moe=56)
        ▼
weights: GGUF (mlock'd in RAM for Qwen3.6; mmap'd from NVMe for Flash; PLE table via lazy/mmap)   KV: VRAM
```

- **Flash reality check:** the full ~80 GB mmap'd model competes with a 32 GB page cache. Your `reports/FRONTIER_EVAL_SCORECARD.md` shows decode falling from 1.71 to 0.13 tok/s as context grows, and TTFT of 12–30 s.
- **Two-model handoff:** the 10.3 s swap latency in the same scorecard is router unload-then-load, and the model reload is dominated by disk.
- **If you used the fork:** the same path, except routed experts would be GPU-resident slots copied over PCIe from host RAM. The cold source must still be resident, or mmap with page-fault risk.

### 5.2 spec-wins vs your benchmark traps

**Conceptual overlap**
- **Same core trap, nearly the same example:**
  - Your `tests/spec_trap/ARCH_SPEC.md` forbids float for currency and cites "$2.675 must stay exact Decimal".
  - spec-wins T3 uses the same 2.675 HALF_UP example.
- **Same decoy structure:** `legacy_limiter.py` plus a contradicting test file mirrors spec-wins' `legacy_window.py` (T1) and the wrong public test.
- **Same hypothesis:** fixes should follow the spec, not the nearest green test.

**Differences that matter**
- **Execution vs text:**
  - spec-wins is agentic. The model runs commands in a real sandbox, and hidden graders execute its code.
  - Your Module 2 is single-shot `chat/completions`, graded from `content` plus `reasoning_content` (per its docstring). Test A forbids float casts in code but, as you softened it, not the word in prose.
  - So it measures stated intent more than a working artifact.
- **Hidden vs visible graders:** spec-wins keeps checks the agent never sees. Your single-shot prompts embed the spec and tests in the prompt, and the grader logic is in the repo.
- **Judgment channel:** spec-wins grades the agent's report. Your suite has Test C (≤ 5 bullet scratchpad), a format constraint rather than judgment.
- **Planner/worker handoff** (`tests/benchmark_suite/pipeline`, `specs/BENCHMARK_ARCH_PLAN.md`) has no spec-wins analogue. It is orthogonal.
- **Tension to resolve:**
  - `harness/pi/SYSTEM.md` forces 3–5 bullet reasoning and `reports/EVAL_REVIEW.md` already judges that "harmful" for the large model.
  - spec-wins shows Flash did well with open exploration (fuzzing, long reports). Test C's constraint may measure instruction following at the cost of capability.

**Lessons to import from spec-wins**
- Add a hidden brute-force oracle (Decimal-from-string).
- Erase slots, `cache-ram` and `/tmp` between runs.
- Judge by reading code.
- Record tool-call counts and wall-clock cost.
- Require a final report that names the decoys.

### 5.3 Upstream llama.cpp vs the fork / moe-cache

**Stay on upstream if:**
- You need the 80 GB Flash model on 32 GB RAM. Both are NVMe/page-cache bound, and the fork has no verified result at this RAM size.
- You want a distribution package, current router/presets and fast follow of new architectures such as `qwen4exp`.
  - Your build already tracks upstream `4d756bc`.
  - Fork branches lag upstream and need matched libraries.
- Stability and multi-slot are priorities. Several fork features are labeled experimental.

**Try the fork (`moe-cache`) if:**
- You run Qwen3.6-35B-A3B-class models, where the whole expert set (~20 GB) fits RAM.
- You want to replace `--cpu-moe` DDR-bound decode with GPU slots.
- The fork's own comparison showed a gain for that exact model, but on a faster card with a 4k context. Expect a smaller or different gain on a 3060 with a 256k context. **[inference]**

**Fork flags worth testing individually even without the cache:**
- `--ple-prefetch` (no CUDA needed, targets Flash's PLE page-ins).
- `--phase-aware-workspace`.
- `--kv-cpu-pinned` with `--kv-gpu-layers` for VRAM relief (on `llama/main`).

**Rules if you try it:**
- Build it in a separate directory and never mix libraries with upstream.
- Test one flag at a time.
- Confirm the grouped path ran via logs.

### 5.4 Operator checklist for Workstation

1. **Verify identity.** Run `llama-server --version` and confirm the binary matches `LLAMA_SERVER_BIN` (upstream `4d756bc`). Confirm no fork build is in use.
2. **Verify model IDs.** `GET /models` should match what clients send. Pi uses `qwen3.8-flash`, the benchmarks send `qwen-3.8-flash`, and the preset section is `qwen3.8-flash` with `alias = qwen-3.8-flash`. The docs say the router overwrites alias, so confirm which name routes. **[uncertain]**
3. **Fix Pi's `contextWindow` for Flash.** 69632 vs 262144 means compaction and overflow handling are wrong. Prefer the `pi-llama-cpp` provider (reads real `n_ctx`) or correct `models.json`.
4. **Dedupe providers.** Run `pi config` and check for built-in `llama.cpp`, `pi-llama-cpp` and the static provider. Remove `apiBaseUrl` if confirmed unused.
5. **Delete or fix `scripts/start_qwen_flash.sh`.**
   - `./models/qwen3.8-flash-3bit.gguf` is a 0-byte file.
   - `--spec-type draft` and `--mtp 3` do not match the upstream flag table (valid: `draft-simple`, `draft-mtp`, …).
   - `--ctk` / `--ctv` / `--ubatch` are not the documented spellings (`-ctk`, `-ub`).
6. **Know which regime each preset is in.**
   - `qwen36-coder`: RAM-resident (`mlock`, `cpu-moe`). Watch memlock limits and swap; the preset itself notes a 32 GB box tight on RAM.
   - `qwen3.8-flash`: NVMe/page-cache bound. Measure page faults and I/O pressure during decode, not just tok/s.
7. **Quantify speculation on Flash.** Compare `spec-type = ngram-mod` vs `none` at the same context. Verification of 48–64 token drafts could worsen paging. **[hypothesis]**
8. **Reasoning-budget interplay.**
   - Server `reasoning-budget = 2048` and Pi `maxTokens = 4096`.
   - For benchmarks, set `max_tokens` large enough that content isn't starved. Your graders already read both fields.
9. **Make benchmark runs reproducible.** Send `temperature: 0`, `seed` and `cache_prompt: false` per request. The preset's `temp = 0.6` otherwise applies. Erase slots (`POST /slots/{id}?action=erase`) and consider `cache-ram`/`cache-idle-slots` between runs. spec-wins and the wiki both do this.
10. **Use hidden oracles.** Grade by executing, not by regex on text. Add the `28.957 EUR`-style float probe.
11. **Context/KV budget on 12 GB.** Keep `fit-target` ≥ 1024 MiB. Flash KV at q4_0 / 69632 ctx and `ubatch = 2048` need checking against the compute buffer. A lower `-ub` cut peak VRAM in the wiki's FreeToken page, at the cost of slower prefill at long context.
12. **Sandbox Pi for unattended runs.** It has no permission system.
13. **If you test the fork:**
    - Do it on Qwen3.6-35B only, with `-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86`.
    - Use `--load-mode none -fit off --moe-expert-cache-size <small> --experimental-logs`, then raise the cache while keeping 1–2 GiB of VRAM free.
    - Check that the grouped counters show `covered > 0`.

### 5.5 Inconsistencies in the sources

- **Model size claims conflict:**
  - spec-wins calls Flash "125B (IQ3_XXS)".
  - Your local docs say 177B/180B at 3.84bpw IQ4_XS-M64 (80 GB on disk).
  - The wiki's Flash Next UD-Q3_K_XL is ~84 GiB, and its IQ3_XXS variant has ~40 GiB of expert data. These may be different quantizations or variants; I couldn't reconcile them. **[uncertain]**
- **"Codacus fork":** spec-wins mentions "Codacus fork, profile cache 88 + MTP" for the Qwen3.6 run. I could not confirm whether it is the same as the GenerelSchwerz fork. **[uncertain]**
- **Windows vs Linux evidence:** all fork performance data is Linux on one machine class. The wiki itself says native Windows performance is unverified.
