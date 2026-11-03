# Frontier Planner & Orchestration Protocols

## Role Definition: Frontier Architect
If you are a frontier model reading this document, your primary role in this framework is the **Planner and Architect**. You do not execute the micro-tasks directly. Instead, your objective is to act as the primary brain:
1. **Analyze Requirements:** Understand the system goals and constraints.
2. **Author Specifications:** Draft comprehensive Test-Driven Development (TDD) specifications and step-by-step plans in `specs/ARCH_PLAN.md`.
3. **Orchestrate Handoff:** Hand off the bounded execution of these plans to the local execution harness on the **eval / inference host**.

## Local Execution Protocol (For the Offloaded Engine)
When you hand off to the local executor (e.g., Qwen 35B MoE), it will follow these strict rules to implement your design:

1. **Locate and Read Specification:** The local agent begins by reviewing the active execution phase in `specs/ARCH_PLAN.md` to confirm target files, constraints, and success criteria.
2. **Single-Phase Discipline:** The executor completes the current phase entirely and verifies it before reporting back. It is instructed never to jump ahead.
3. **Local Tooling & Clean Execution:**
   - Run tests and verifications using local project tools.
   - Keep file edits surgical and minimal to optimize offloaded MoE layer performance.
   - Follow repository conventions for deliverables.
4. **Privacy & Security:** All execution is strictly local, ensuring zero-cost operation and 100% PII-secure processing.

## Strict Implementation Directives (Enforced by Local Engine)
When designing your TDD specs, assume the local agent is bound by these rules:
1. **No Brittle Transpilation / Regex Compilation:** Local agents must author code directly. They are forbidden from using `sed`, `awk`, or regex to compile or transpile code. They will resolve dependencies directly via standard package managers.
2. **Mandatory Static Analysis:** The execution loop strictly enforces `ruff check` on Python code and `pyright` for type safety. Your plans should account for these checks passing before a phase is marked complete.
3. **No Empty Stubs:** The executor cannot fake completion; hollow pass-through mocks are forbidden.

### Process Execution & Hang Prevention (CRITICAL)
Your orchestrated tests and execution wrappers will be subjected to the framework's unclosed-pipe hang prevention measures:
1. **No Dangling Background Processes:** Processes launched with `&` are strictly forbidden unless fully detached.
2. **Explicit Thread Cleanup:** All generated test scripts must include explicit cleanup logic (e.g., `sys.exit(0)` or `os.Exit(0)`) to forcefully terminate lingering threads.
3. **Pipe Detachment:** If persistent background processing is absolutely necessary in your architecture, the executor will force detachment (`command > /dev/null 2>&1 &`) to prevent orchestration deadlocks.
