# ADR-0014 — A dynamic, typed and inheritable workflow

- **Status:** Accepted
- **Date:** 2026-08-30
- **Refines:** [ADR-0013](0013-resource-as-unit-of-sharing.md) (it gives shape to the
  `workflow` resource and adjusts the access default per resource type)

## Context

The demand's cycle was undefined (SP-4's core). The product decided: **the human↔agent
development flow is dynamic** — the platform has a default, but each account, workspace,
project and even a specific demand may work its own way. The chat screen and the agent have
to understand any flow without knowing any of them: the flow is **data**, not code.

The market's references occupy the extremes: Jira customizes only statuses (no artifacts, no
agent); GitHub Actions is flow-as-code for a machine, not for human follow-up; BPMN models
everything and costs an analyst. The middle ground — typed stages + free composition — is
vacant.

## Decision

1. **Stages have a semantic type; flows are compositions.** The type vocabulary belongs to
   the platform: `context`, `spec`, `plan`, `implementation`, `test` (subtypes `aaa`, `e2e`,
   `integration`), `human_validation`, `finalization`, `generic`. The type determines the
   **renderer** on the screen and the agent's **behaviour** (which artifact to produce, where
   to stop). A new type requires an evolution of the platform; a new composition does not.
2. **The v1 structure, deliberately simple:**
   ```
   Flow { name, version, stages: [
     { key, name, type, artifacts: [document|spec|plan|test_plan|…],
       gate: human | none, substages? } ] }
   ```
   **Where an artefact lives (added 2026-09-03):** as a file at `demand/<id>/<kind>.md` in the
   project's root repository — [ADR-0028](0028-project-knowledge-as-a-git-repository.md).
   "Puts an artifact on the table" means that file exists at that path. Rendered bytes
   (a diagram's export) stay in the `ObjectStore`, referenced from the file.
   No conditionals, no stage parallelism, no rules DSL — they evolve over the same structure.
3. **A resolution chain with inheritance:** `platform ◁ account ◁ workspace ◁ project ◁
   demand` — the nearest level wins; it is inherited by omission, overridden by declaration.
   The interface always shows **where the effective flow came from**.
4. **The demand freezes the flow's version when it starts.** A stage's progress is an event
   (ADR-0006); the ruler on the screen is a projection.
5. **Promotion:** a flow created at one level may be promoted to a level above (demand →
   project → workspace → account) by whoever has `manage`.
6. **An access default per resource type** (a refinement of ADR-0013): a resource **with a
   credential** (`integration`) stays closed — a grant composed in the invite; a **content**
   resource (`workflow`, `skill`, `git_flow`) in an organization account is **open within the
   account by default**, restrictable by a grant. A credential is risk; a flow is knowledge —
   opposite defaults are the right policy.
7. **The v1 sharing scopes:** private → account. **External** sharing (between accounts / a
   community catalogue) stays out of v1 — a strategic decision recorded as P-9: it waits, it
   does not sleep.
8. **The platform's default flow** (the catalogue, level 0): context → spec → plan →
   implementation → test (aaa/e2e/integration) → human validation → finalization.

## Alternatives considered

**Fixed platform stages.** It was the earlier design (and the old PRD's). Rejected: accounts
work differently, and the cost of dynamism fell to almost zero with typed stages — the static
case becomes the particular case of a single flow.

**A full workflow engine (BPMN/Temporal).** Rejected in v1: it buys conditionals and
parallelism nobody asked for at a price in complexity everybody would pay.

**Flow as code (a YAML per repo).** Rejected as the primary interface: the audience is the
dev-as-manager on the screen, not a pipeline; nothing prevents a future export.

## Consequences

- ➕ It closes SP-4's core: the demand's cycle is the effective flow resolved by the chain.
- ➕ The renderers are dop-app's orphan components promoted per type (validation with a
  checklist, finalization with steps, MD documents, test tabs).
- ➕ The "dynamic process", deferred by the old PRD to post-MVP, becomes the model — with no
  extra screen cost, because the screen never knew fixed stages.
- ➖ The inheritance chain requires a visible trail ("inherited from…") — without it, it
  becomes a support ticket.
- ➖ P-8 stays open: the syntax of the executable criteria inside the `spec` artifact.
