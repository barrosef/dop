# ADR-0017 — A microVM per demand, with a single shared worktree

- **Status:** Accepted; the verification clause is superseded by ADR-0023
- **Date:** 2026-08-31
- **Relations:** relies on ADR-0007; knowledge boundary set by ADR-0021; verification location by ADR-0023

## Context

A demand has one main agent and N subagents (ADR-0007). Where each runs, and
where the application under test runs, are separate decisions.

## Decision

1. **One microVM per demand** (`SandboxLauncher`; tiers `namespace` and
   `hardware`). The hard isolation boundary is between accounts and between
   demands. The database enforces one live sandbox per demand:
   `UNIQUE (demand_id) WHERE state <> 'destroyed'`.
2. **One worktree, `/workspace`, shared by the demand's threads.** Two
   threads editing the same file may conflict; accepted. If practice
   requires it, one worktree per thread is the mapped evolution.
3. **The knowledge boundary is the project**, not the demand: every sandbox
   of a project clones the project root repository at `/project`
   (ADR-0021). The workspace boundary stays per demand.
4. **Verification does not run in the sandbox.** It runs in an ephemeral
   runner built from a commit (ADR-0023). The demand's address is
   `<service>--<demand>.<domain>`; parallel verification runs of one demand
   queue.
5. **Isolation tiers are honest:** asking for `hardware` where the executor
   cannot provide it (k3d has no Kata runtime) is refused, never downgraded.
6. **Provisioning is by explicit call** (the trigger is open —
   `ROADMAP.md` P-24).

## Alternatives considered

- **One microVM per thread** — rejected: N× overhead for cooperating agents.
- **One git worktree per thread** — deferred; `ExecRequest` would carry a
  thread.
- **Tests inside the agent's sandbox** — rejected: the working tree is not a
  commit (ADR-0005, ADR-0023).

## Consequences

- Two compute lifecycles: the demand's long sandbox and the verification's
  short runner.
- A test requires a published commit: edit → commit → verify.
- The `hardware` tier is exercised only on clusters with Kata
  (`ROADMAP.md` P-28).

## Revisions

- 2026-09-03 — the address is per demand; parallel runs queue.
- 2026-09-04 — "an ephemeral pod per verification run" replaced by the
  runner of ADR-0023.
