# Metrotower AI Stack Architecture

## Overview
This document outlines the architecture for the `berserker` repository's local AI stack, designed to run entirely on the "Metrotower" workstation (Ryzen 7 9700X, RTX 3060 12GB VRAM, 32GB DDR5). 

The stack is designed around a **Frontier-to-Local Handoff Workflow**:
1. Frontier models (e.g., Gemini, Claude) generate stage-gated architectural plans (`ARCH_PLAN.md`).
2. Local harnesses execute the code completely offline, keeping PII secure and avoiding massive token costs.

---

## Component Architecture

```mermaid
flowchart TD
    subgraph Cloud [Cloud / Frontier]
        A[Frontier Model / Antigravity] -->|Writes| B(specs/ARCH_PLAN.md)
    end
    
    subgraph Local [Metrotower Workstation]
        B --> C{Orchestration Harness}
        
        C -->|Command Line / CLI| D[Pi Coding Agent]
        C -->|Background Batch| E[n8n Docker Container]
        
        D -->|OpenAI API| F[llama-server Engine]
        E -->|OpenAI API| F
        
        F --> G[qwen36-coder MoE]
        F --> H[glm47-reap Fallback]
    end
    
    subgraph Guardrails [Context Boundaries]
        I[SYSTEM.md / AGENTS.md] -.-> D
        J[JSON Schemas / Nodes] -.-> E
    end
```

---

## 1. The Execution Engine (`engine/`)
The bedrock of the stack is the `llama.cpp` server optimized for the RTX 3060.
* **API:** Exposes a standard OpenAI-compatible endpoint at `http://127.0.0.1:8080/v1`.
* **Hardware Profile:** Uses a `-cpu-moe` strategy. The massive 35B model parameters are pinned into system DDR5 RAM via `mlock` (requiring `ulimit -l` modifications), leaving the 12GB VRAM entirely free for ultra-fast attention caching and context limits.
* **Presets:** Managed via `engine/models.ini` (e.g., `[qwen36-coder]`, `[glm47-reap]`).

## 2. Context Guardrails (`specs/` & `prompts/`)
Local models easily degrade into infinite reasoning loops (e.g., generating 40,000 characters over 280 seconds without producing code). 
* **The Fix:** The `prompts/local_agent_system_prompt.md` acts as a hard boundary, forcing the MoE to restrict its scratchpad reasoning to 3-5 concise bullet points.
* **The Spec:** `specs/ARCH_PLAN_TEMPLATE.md` mandates that the frontier model breaks tasks down into isolated, single-step phases, allowing the local engine to operate with a fresh context per step (Amnesia by Design).

## 3. Background Automation Harness (`automation/n8n/`)
For background, cron-based tasks like PII stripping or email triage.
* **Deployment:** Containerized in Docker using `network_mode: host` to achieve zero-overhead connectivity to the local engine.
* **Workflows:** Utilizes zero-credential HTTP nodes or `n8n-nodes-base.openAi` nodes mapped strictly to `localhost:8080/v1`, enforcing strict JSON parsing (e.g., `email_triage_workflow.json`).

## 4. Local Coding Harness (`harness/pi/`)
The interactive terminal agent used by the developer to execute the `ARCH_PLAN.md`.
* **Framework:** Powered by the [Pi coding agent](https://pi.dev) via Node.js/npm.
* **Integration:** Connects natively to `llama-server` using `pi-llama-cpp`.
* **Context Engineering:** `SYSTEM.md` and `AGENTS.md` are configured in the repository root to automatically inject the local guardrails and instruct Pi to read the `ARCH_PLAN.md` before executing file edits.
* **Optimization:** Because Pi sends context deltas instead of full histories, prompt prefill speeds hit ~1,000 tokens/second by reusing the engine's chunk cache.
