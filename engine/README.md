# Workstation Local AI Engine (`engine/`)

This directory contains the core engine runtime configurations, startup tooling, and system tuning for running large MoE coding models on the **Workstation** workstation.

---

## 1. Workstation Hardware Profile

* **CPU:** AMD Ryzen 7 9700X (8 Cores, 16 Threads, Single CCD, 32 MiB L3 Cache)
* **System RAM:** 32 GB DDR5-6000 CL36 (2 × 16 GB dual-channel, ~60–65 GB/s Infinity Fabric read ceiling)
* **Discrete GPU:** NVIDIA GeForce RTX 3060 12 GB GDDR6 (headless, dedicated compute on PCIe 4.0 x16)
* **Display Output:** AMD Ryzen RDNA2 iGPU (`/dev/dri/card1`, DP-2)
* **Storage & Swap:** Samsung 990 Pro NVMe (Btrfs, zstd:3) with a dedicated 33 GB NVMe swap partition
* **Software Stack:** Arch Linux LTS (Kernel `6.18.53-1-lts`), NVIDIA Driver `615.71.09`, CUDA `13.4`, `llama.cpp-cuda` b10631 (`/usr/bin/llama-server`)

---

## 2. Architecture & File Layout

```
engine/
├── models.ini                  # Single source of truth for presets ([*], [qwen36-coder], etc.)
├── workstation.env              # Environment variable defaults (paths, port, default preset)
├── bin/
│   ├── ini2args.py             # Parses models.ini sections into CLI arguments
│   ├── preflight.sh            # Hardware, memory, VRAM, port, and Ollama validation script
│   ├── llama-up.sh             # Startup script (single-model or router mode; foreground or daemon)
│   ├── llama-down.sh           # Safe shutdown script for background engine
│   └── setup-memlock.sh        # Diagnostic and installation helper for RLIMIT_MEMLOCK
├── run/                        # Runtime state (PID files, logs) - gitignored
├── system/
│   ├── 90-hybrid-ai-harness-memlock.conf      # PAM limits configuration (/etc/security/limits.d/)
│   └── user@.service.d/memlock.conf   # Systemd user manager drop-in
├── systemd/
│   └── hybrid-ai-harness-llama.service        # User unit for systemd management
└── README.md                   # This specification and operations manual
```

---

## 3. Flag Rationale & Technical Deep-Dive

All presets in `models.ini` inherit from global section `[*]`. Each non-obvious flag addresses specific hardware and algorithmic constraints of Workstation:

### Threads (`threads = 7`, `threads-batch = 7`)
The Ryzen 7 9700X is a single-CCD 8-core CPU. CPU MoE expert matrix multiplications are strictly memory-bandwidth bound. On dual-channel DDR5-6000, read bandwidth caps at ~60–65 GB/s. Active expert weights take ~0.6 GB per token:
$$\text{Theoretical decode ceiling} \approx \frac{60\text{ GB/s}}{0.6\text{ GB/token}} \approx 100\text{ tok/s}$$
In practice, 7 physical threads saturate the Infinity Fabric memory interface (~50–65 tok/s). SMT siblings add cache contention without increasing memory bandwidth. Allocating 7 threads on 7 physical cores reserves 1 full core and all SMT threads for Wayland compositor rendering, CUDA driver submission, and HTTP worker threads.

### Load Mode (`load-mode = mlock`)
llama.cpp b10631 deprecates `--no-mmap` and `--mlock` in favor of `--load-mode {auto,none,mmap,mlock,mmap+mlock,dio}`. Setting `load-mode = mlock` reads the weights into DDR5 RAM and locks them (`mlock(2)`). This prevents Linux kernel page reclamation from pushing expert layers to NVMe swap during background tasks.

### Batch & Micro-Batch (`batch-size = 2048`, `ubatch-size = 2048`)
Prompt prefill processes attention on the GPU while routing expert operations. Larger physical batches amortize the PCIe transfer latency of CPU-resident expert tensors during op-offload.

### Quantized KV Cache (`cache-type-k = q8_0`, `cache-type-v = q8_0`)
Qwen3.6 (`qwen35moe`) is a hybrid recurrent model:
* Total layers: 40
* `full_attention_interval = 4`: Only **10 layers** have full self-attention KV caches.
* The remaining 30 layers use Gated-DeltaNet recurrent linear attention (fixed state size of ~63 MiB per slot).
* With 2 KV heads and 256 head dimension:
  $$\text{KV per token (f16)} = 10 \times 2 \times 2 \times 256 \times 2\text{ bytes} = 20\text{ KiB}$$
  $$\text{KV per token (q8\_0)} = 10 \times 2 \times 2 \times 256 \times 1.0625\text{ bytes} \approx 10.6\text{ KiB}$$
For full 262k context ($262,144$ tokens):
* **f16 KV:** $5.00\text{ GiB}$
* **q8_0 KV:** $2.66\text{ GiB}$ (saves $\approx 2.34\text{ GiB}$ VRAM)
* **q4_0 KV:** $1.41\text{ GiB}$
Because q8_0 requires only 2.66 GiB, the full native 256k context comfortably fits within the 12 GB RTX 3060 alongside model weights without needing exotic quantization. Quantized V requires `flash-attn = on`.

### Context Checkpoints vs. KV Shifting
* Pure attention models (e.g. `glm47-reap`, DeepSeek MLA) support KV shifting (`cache-reuse = 256`).
* Recurrent hybrid models (Qwen3.6) cannot perform KV shifting across linear attention recurrent states. Instead, prefix reuse relies on context checkpoints (`ctx-checkpoints = 8`, `checkpoint-min-step = 2048`), which store recurrent state snapshots in DDR5 host RAM (~500 MiB total).

### Host Prompt Cache RAM (`cache-ram = 2048`)
The llama-server default (`cache-ram = 8192` MiB) is unaffordable on a 32 GB system where ~20 GB is already dedicated to pinned MoE experts. Capping `cache-ram` at 2048 MiB keeps host RAM usage bounded.

### Dual Slots & Unified KV (`parallel = 2`, `kv-unified = true`)
Enables two concurrent execution slots (e.g., interactive coding agent + background n8n triage workflow) drawing from a single unified dynamic KV memory pool.

### VRAM Headroom (`fit-target = 1024`)
Reserves 1024 MiB of VRAM for CUDA allocator fragmentation and temporary buffers. Because the desktop display now runs on the Ryzen iGPU, the 4 GiB display margin previously required for Ollama is no longer needed.

### Anti-Loop Guardrails (`reasoning-budget = 2048`, `reasoning-budget-message`)
Prevents unbounded reasoning loops. Empirical benchmarks in `experiments/rate_limiter/qwen_benchmark_metrics.json` showed unbudgeted Qwen reasoning executing 12,288 thinking tokens with 0 content tokens over 280 seconds in a degenerate loop. With budgeting enabled, tasks complete cleanly in under 6 seconds.

### Sampling Parameters (`repeat-penalty = 1.0`)
Coding tasks require `repeat-penalty = 1.0`. The running server had `repeat-penalty = 1.1`, which penalizes syntactically necessary repeated characters (braces, closing brackets, indentation, variable names).

---

## 4. Memory Budget & Allocation Table

| Model Preset | Model File Size | GPU Layers / Placement | VRAM Usage (Weights + q8_0 KV) | DDR5 Host RAM (Experts + Cache) | NVMe Swap Risk | Target Tok/s (Decode) |
|---|---|---|---|---|---|---|
| **Running Baseline** (PID 337100) | 22.1 GB | All non-expert on GPU | 8.4 GB (f16 KV, 3 threads) | ~19.5 GB pinned | High (8.8 GB in swap) | ~30 tok/s |
| **`[qwen36-coder]`** (Default) | 20.6 GiB (22.1 GB) | `cpu-moe` (non-expert on GPU) | ~6.3 GiB (q8_0 KV + 1 GiB headroom) | ~19.5 GiB experts + 2.0 GiB cache | Low-Medium | ~50–65 tok/s |
| **`[qwen36-coder-hybrid]`** (Candidate) | 20.6 GiB (22.1 GB) | `n-cpu-moe 32` (8 expert layers on GPU) | ~10.2 GiB (fits in 12 GiB VRAM) | ~15.6 GiB experts + 2.0 GiB cache | Very Low (frees 3.9 GiB DDR5) | ~60–75 tok/s |
| **`[glm47-reap]`** (Alternative) | 13.1 GiB (14.1 GB) | `cpu-moe` (MLA attention on GPU) | ~4.7 GiB (128k ctx q8_0) | ~13.0 GiB experts + 2.0 GiB cache | Minimal (safest for heavy Docker) | ~65–80 tok/s |

---

## 5. TurboQuant KV Fork Option

The original specification referenced TurboQuant KV compression for 128k–256k context. In `llama.cpp-cuda` b10631, TurboQuant is **not implemented**. Allowed `-ctk` and `-ctv` options are:
`f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1`.

**Why TurboQuant is not needed for Phase 1:**
Because Qwen3.6 is a hybrid model with only 10 attention layers, 256k context at `q8_0` consumes only 2.66 GiB of VRAM. The RTX 3060 has 12 GB, leaving over 5.5 GB of free VRAM with `[qwen36-coder]`.

**Optional Fork Path:**
If TurboQuant KV is required for larger dense models or full-attention 512k context in Phase 4:
1. Clone the TurboQuant fork repository into `experiments/turboquant-build/`.
2. Build with CUDA support: `cmake -B build -DGGML_CUDA=ON && cmake --build build --config Release -j 8`.
3. Point `LLAMA_SERVER_BIN` in `engine/workstation.env` to the custom binary.
4. Evaluate quality and tok/s against baseline q8_0 via `validation/run_suite.py`.

---

## 6. System Limit Configurations (mlock, Swappiness, Ollama)

### 1. Memory Locking (RLIMIT_MEMLOCK)
Workstation's current default limit is `ulimit -l = 8192 KB` (8 MiB). When `llama-server --load-mode mlock` runs under this limit, the `mlock()` syscall fails with `ENOMEM`, printing a warning and leaving `VmLck: 0 kB`.

To configure unlimited memory locking:
Run the diagnostic and installer helper:
```bash
# Check current limit status:
engine/bin/setup-memlock.sh

# Install system configuration (requires sudo):
sudo engine/bin/setup-memlock.sh --install

# Re-execute user session systemd daemon:
systemctl --user daemon-reexec
```
Files provided:
* `engine/system/90-hybrid-ai-harness-memlock.conf` -> `/etc/security/limits.d/90-hybrid-ai-harness-memlock.conf`
* `engine/system/user@.service.d/memlock.conf` -> `/etc/systemd/system/user@.service.d/memlock.conf`

### 2. Swappiness Tuning (`vm.swappiness = 10`)
Workstation has a 33 GB NVMe swap partition with `vm.swappiness = 60`. Under memory pressure, the kernel aggressively pages out inactive anonymous memory even when NVMe read bandwidth is high. To reduce swap thrashing:
```bash
sudo sysctl vm.swappiness=10
echo "vm.swappiness = 10" | sudo tee /etc/sysctl.d/99-hybrid-ai-harness-swap.conf
```

### 3. Ollama Contention Management
Ollama runs as a background systemd service on port `11434`. If an Ollama model is loaded while `llama-server` is active, it contends for the 12 GB VRAM and DDR5 bandwidth:
```bash
# Check if Ollama has loaded models:
curl -s http://127.0.0.1:11434/api/ps

# Stop Ollama if not in use:
sudo systemctl stop ollama
# Or prevent auto-start:
sudo systemctl disable --now ollama
```

---

## 7. Migration & Operations Guide

### Preflight Verification
Before starting or switching presets, run `preflight.sh` to check hardware readiness:
```bash
engine/bin/preflight.sh --preset qwen36-coder
```

### Migrating the Running Server (PID 337100)
To migrate from the old configuration (PID 337100: 3 threads, repeat-penalty 1.1, f16 KV) to the tuned preset:

1. **Stop the running server:**
   ```bash
   engine/bin/llama-down.sh --force
   ```
2. **Apply system limits (one-time setup):**
   ```bash
   sudo engine/bin/setup-memlock.sh --install
   systemctl --user daemon-reexec
   ```
3. **Verify preflight passes:**
   ```bash
   engine/bin/preflight.sh --preset qwen36-coder
   ```
4. **Launch the engine:**
   * **Option A: CLI daemon:**
     ```bash
     engine/bin/llama-up.sh single qwen36-coder
     ```
   * **Option B: Systemd user service:**
     ```bash
     mkdir -p ~/.config/systemd/user/
     cp engine/systemd/hybrid-ai-harness-llama.service ~/.config/systemd/user/
     systemctl --user daemon-reload
     systemctl --user enable --now hybrid-ai-harness-llama.service
     systemctl --user status hybrid-ai-harness-llama.service
     ```

### Stopping the Engine
```bash
engine/bin/llama-down.sh
```
Or if running as a systemd user unit:
```bash
systemctl --user stop hybrid-ai-harness-llama.service
```

### Checking Status & Health
```bash
curl -s http://127.0.0.1:8080/health
curl -s http://127.0.0.1:8080/metrics
tail -f engine/run/llama-server.log
```
