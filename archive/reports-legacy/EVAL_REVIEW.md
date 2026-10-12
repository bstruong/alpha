# Evaluation of Previous Tuning for Qwen3.8-Flash-Next (180B)

## 1. Performance Parameter Adjustments

### `load-mode = mmap`
**Evaluation: Conceptually Valid & Absolutely Necessary**
The real 180B model at 3-bit quantization will be roughly 67.5GB in size. Our target hardware (Workstation) only has 32GB of system RAM and 12GB of VRAM. Because the model vastly exceeds the combined physical memory limits, `mlock` would immediately trigger an OOM. `mmap` allows the OS to transparently page weights directly from the NVMe SSD to RAM/VRAM as needed. This is the only way a 180B model can run on this hardware.

### `--n-cpu-moe 56`
**Evaluation: Conceptually Valid & Necessary**
Given the massive size of the 180B model, we must aggressively offload the MoE (Mixture of Experts) layers to the CPU/RAM (and subsequently to NVMe via mmap) to save VRAM for attention layers and context. Offloading 56 layers ensures maximum VRAM savings, avoiding instant VRAM OOMs during inference. 

### `q4_0` KV Cache Limits
**Evaluation: Conceptually Valid & Necessary**
A 180B parameter model typically features significantly wider hidden dimensions, more heads, and more layers than a 35B model, which directly multiplies the KV cache size per token. Using 8-bit or 16-bit KV cache would consume VRAM extremely rapidly, limiting context size. Using `q4_0` for the KV cache keeps the memory footprint manageable and allows us to retain larger context windows.

## 2. Cognitive System Prompt Updates

### 3-5 Bullet Reasoning Limits & Architectural Supremacy
**Evaluation: Conceptually Invalid & Harmful**
These aggressive constraints were introduced as a band-aid because we incorrectly believed the 177B model was failing reasoning and spec traps (when it was actually the 35B model). A true frontier 180B model possesses vastly superior reasoning capabilities. Forcing a 3-5 bullet limit on a 180B model will artificially choke its chain-of-thought (CoT), leading to degraded performance on complex multi-file architectural tasks. We should remove or heavily relax these prompt hacks to allow the 180B model to fully utilize its latent cognitive capacity.
