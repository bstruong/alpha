# Hybrid AI Orchestration Framework

## Overview

The Hybrid AI Orchestration Framework is an advanced architectural pattern designed to seamlessly integrate high-reasoning frontier models with highly efficient local AI engines. By leveraging a "Frontier-to-Local" approach, this system guarantees both scalable, complex planning and robust, zero-cost execution within a highly secure environment. 

## Frontier-to-Local Architecture

The core of the framework lies in the strict separation of concerns:

- **Frontier Agents (Planners and Architects):** High-capacity frontier models are utilized strictly for strategic planning, architectural design, and generating precise specifications. These models operate primarily by authoring `specs/ARCH_PLAN.md` files and establishing Test-Driven Development (TDD) specifications.
- **Local Offloaded Models (Executors):** Bounded execution tasks are systematically handed off to local offloaded models (e.g., Qwen 35B MoE). These agents process instructions against the pre-established plans. Execution occurs at zero marginal cost and guarantees 100% data privacy for Personal Identifiable Information (PII-secure processing).

This asymmetric processing architecture enables a robust workflow, scaling inference capabilities while protecting sensitive environments on the **AM5 homelab** (production and staging/test for local inference and Alpha evals). Primary software development is via Cursor cloud agents; the Haswell desk machine is an operator seat only — see [`docs/infrastructure-topology.md`](docs/infrastructure-topology.md).

## Key Capabilities & Features

### Engine Lifecycle Management
The framework dynamically scales and handles hardware constraints automatically:
- **Auto Spin-up:** Immediate, on-demand readiness of local models when a planner initiates a task specification handoff.
- **RAM Flush:** Automated VRAM/RAM cleanup processes and memory purging after execution to ensure system stability and optimize the availability of local hardware resources.

### Sidecar Telemetry Logging
Provides comprehensive visibility into the execution pipeline:
- Tracks execution metrics across local runtimes.
- Delivers real-time, asynchronous logging via isolated sidecar instances without blocking the main orchestration or agent execution threads.

### Unclosed-Pipe Hang Prevention
A robust process execution supervisor automatically detects and isolates dangling background processes, ensuring test scripts and execution loops cleanly terminate. Persistent pipes are forcefully detached to prevent orchestration locks and hang states.

### TDD Execution Loops
Built on rigorous validation principles, the local executor loop constantly verifies output against the specifications and tests designated by the frontier planner. Execution is single-phase and verification-gated to prevent context drift, hallucination, and incomplete implementations.

## Implementation Details

All task handoffs follow strict conventions, emphasizing minimal context churn, mandatory static analysis (e.g., `ruff check`, `pyright`), and self-contained executions. For detailed operational procedures and exact planner roles, please refer to the agent orchestration directives.
