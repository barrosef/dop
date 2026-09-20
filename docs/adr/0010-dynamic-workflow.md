# ADR-0010 — A dynamic, typed and inheritable workflow

- **Status:** Accepted
- **Date:** 2026-08-30
- **Relations:** refines ADR-0009; relies on ADR-0004 (stage progress is an event), ADR-0021 (artifact location)

## Context

The human↔agent development flow is configurable per account, workspace,
project and demand. The cockpit and the agent must operate any flow without
knowing a specific one: the flow is data.

## Decision

1. **Stages have a semantic type; flows are compositions of stages.** The
   type vocabulary belongs to the platform: `context`, `spec`, `plan`,
   `implementation`, `test` (subtypes `aaa`, `e2e`, `integration`),
   `human_validation`, `finalization`, `generic`. The type selects the
   renderer in the cockpit and the agent's behaviour (artifact to produce,
   where to stop). A new type is a platform change; a new composition is
   not.
2. **Structure (v1):**
   ```
   Flow { name, version, stages: [
     { key, name, type,
       artifacts: [document | spec | plan | test_plan | …],
       gate: human | none,
       actions?: [{ on: enter | exit, name, params }],
       substages? } ] }
   ```
   No conditionals, no parallel stages, no rules language.
   - **An artifact is a file** at `demand/<id>/<kind>.md` in the project
     root repository (ADR-0021). Rendered binaries stay in the
     `ObjectStore`, referenced from the file.
   - **Stage actions** are drawn from a closed vocabulary the platform
     implements — `open_attention`, `close_attention`, `send_email`,
     `provision_bench` — with `params` as a flat string map. An action name
     may not repeat at the same moment of one stage (the idempotency key is
     `(event, flow/version/stage/moment, action name)`; such a flow is
     refused on write).
3. **Resolution chain with inheritance:** `platform ◁ account ◁ workspace ◁
   project ◁ demand`; the nearest declared level wins. The interface shows
   the level the effective flow came from.
4. **A demand freezes the flow's version when it starts.** A stage's
   progress is an event; the stage ruler is a projection.
5. **Promotion:** a flow may be promoted to a higher level (demand → project
   → workspace → account) by a holder of `manage`.
6. **Access defaults per resource kind** (refining ADR-0009): a resource
   with a credential (`integration`) is closed by default (grant composed
   in the invite); a content resource (`workflow`, `skill`, `git_flow`) in an
   organization account is open within the account by default, restrictable
   by grant.
7. **Sharing scopes (v1):** private → account. External sharing between
   accounts and a community catalogue are out of v1 (`ROADMAP.md` P-9).
8. **The platform's default flow:** context → spec → plan → implementation
   → test (aaa / e2e / integration) → human validation → finalization.

## Alternatives considered

- **Fixed platform stages** — rejected: accounts work differently; typed
  stages make the static case a particular flow.
- **A workflow engine (BPMN, Temporal)** — rejected for v1: conditionals and
  parallelism not required.
- **Flow as code (YAML per repository)** — rejected as the primary
  interface; an export remains possible.

## Consequences

- Stage renderers in the cockpit are per type.
- The inheritance chain requires the "inherited from" trail in the interface.
- The syntax of executable criteria in the `spec` artifact is open
  (`ROADMAP.md` P-8).

## Revisions

- 2026-09-03 — decision 2: artifacts are files in the project root
  repository.
- 2026-09-06 — decision 2: stage actions.
