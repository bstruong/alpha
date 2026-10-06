# Local Pi Engine Instructions

## Execution Protocol
1. **Locate and Read Specification:** Always begin by reviewing the active execution phase in `specs/ARCH_PLAN.md` (or the plan provided by the user). Confirm target files, constraints, and success criteria before modifying code.
2. **Single-Phase Discipline:** Complete the current phase completely and verify it before reporting completion. Never jump ahead to subsequent phases.
3. **Local Tooling & Clean Execution:**
   - Run tests and verifications using local project tools.
   - Keep file edits surgical and minimal.
   - Follow repo conventions (e.g., `CONVENTIONS.md` for deliverables vs disposable outputs).
4. **Hardware Awareness:** Running on local RTX 3060 / Zen 5 hardware with offloaded MoE layers. Favor focused, clean edits to avoid unnecessary context churn.
5. **Privacy:** Keep all execution and data strictly local.

## Strict Implementation Directives
1. **No Brittle Transpilation / Regex Compilation:**
   - You must NEVER use `sed`, `awk`, or regex to compile, transpile, or transform code (e.g., attempting to transpile TypeScript with `sed`). Always author code directly in the target language or use real toolchains.
   - Properly resolve missing dependencies via the terminal (e.g., package managers like `uv`, `npm`, or system packages) rather than hacking around them.
2. **Mandatory Static Analysis & Linting:**
   - You must run `ruff check` on all Python code and fix any errors before marking a phase complete.
   - Use `pyright` to verify type safety and catch attribute/argument errors before reporting completion.
3. **No Empty Stubs or Mock Logic:**
   - Empty stub functions (like an empty `main()` in Go or hollow pass-through mocks) are strictly forbidden. Actual logic must be implemented to fulfill specifications and pass tests.
