# Experiment 2: Rigorous Test-Driven Validation

## Objective
Remediate the "green-washing" flaws of Experiment 1 by enforcing strict Test-Driven Development (TDD), modern static analysis (`uv`, `ruff`, `pyright`), and self-correction loops on the local Qwen model.

## Core Directives

### 1. Cloud-Mandated TDD
The Frontier model (Antigravity) will write immutable Unit Tests directly into the spec. Qwen is only permitted to write implementation code and cannot modify the test files.

### 2. Strengthened `AGENTS.md` Constraints
* Forbid brittle transpilation (e.g., using `sed` on TypeScript).
* Require proper resolution of missing dependencies (install via terminal).
* Forbid empty `main()` mocks.

### 3. Self-Correction Reflection Loop
The Pi CLI invocation must include a directive forcing Qwen to act as a Senior Reviewer on its own code before marking the phase complete.

### 4. Modern Python Toolchain (`uv`, `ruff`, `pyright`)
The local harness must be equipped with modern, Rust-based Python tooling.
* **uv:** For instantaneous, cached package management without network hangs.
* **ruff:** For sub-second linting and formatting. Code must pass `ruff check` before submission to catch `UnboundLocalError` and scope bugs.
* **pyright:** For static type checking to prevent hallucinated attribute errors (like the `argparse` missing argument crash).
