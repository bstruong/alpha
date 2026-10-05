# Architectural Spec: [Project/Feature Name]

## 1. Objective
[Brief description of what is being built]

## 2. Architecture & Design
[High-level architecture, components, and data flow. Designed by Frontier Model (Claude/GPT-4/Gemini).]

## 3. Bounded Execution Phases
*These phases are designed to be executed sequentially by the local MoE coding engine. Context should be reset between phases.*

### Phase 1: [Name of Phase]
- **Goal:** [What to achieve]
- **Files to Modify:** 
  - `path/to/file1`
  - `path/to/file2`
- **Execution Constraints:** [e.g., "Do not modify the database schema"]
- **Success Criteria:** [How the local agent knows it is done]

### Phase 2: [Name of Phase]
- **Goal:** [What to achieve]
- **Files to Modify:** 
  - `path/to/file3`
- **Execution Constraints:** []
- **Success Criteria:** []

## 4. Guardrails & Notes
- Avoid scope creep. Stick exactly to the boundaries of the current phase.
- Use the provided system prompts to limit reasoning length.
