# ADR-0005 — No green, no PR: native verification, and a merge queue per repository

- **Status:** Accepted
- **Date:** 2026-08-29
- **Relations:** refined by ADR-0011 (the orchestrator detects overlap), ADR-0021 (where the `spec` artifact lives), ADR-0023 (where verification runs)

## Context

Agents deliver pull requests faster than humans review them, and parallel
demands on one repository produce PRs each verified against an outdated
`main`. A merge is a human decision (product rule); what precedes it and
what follows it are the platform's.

## Decision

### Before the pull request

1. **Acceptance criteria are executable and live in the demand's `spec`**
   artifact (`demand/<id>/spec.md`, ADR-0021): test suites (unit, AAA, e2e)
   and checks derived from the spec.
2. **No PR opens with acceptance failing.** The agent iterates to green; a
   persistent failure becomes an attention item with a question to the
   human.
3. **A critic reviews before the human:** an independent model instance with
   a clean context receives diff + spec + evidence and issues a verdict. The
   critic runs on a strong model at maximum effort (ADR-0008).
4. **The PR carries the evidence package:** acceptance results, test runs,
   the critic's verdict, links to the trace.

### After the green

5. **A merge queue per repository is a domain concept.** A green PR enters
   the queue; the queue reapplies each PR onto the current `main`, re-runs
   verification and merges one at a time.
6. **A conflict is first the demand agent's task** (rebase and resolution);
   a failure escalates to the human through the attention box.
7. **Overlap between active demands is detected before the PR** by the
   project orchestrator (ADR-0011).
8. **The provider's native queue is used where it exists** (GitHub merge
   queue, GitLab merge trains) through `GitProvider`; the platform's queue
   orchestrates on top and covers providers without one.

## Alternatives considered

- **Human-only review** — rejected: review capacity is the bottleneck.
- **Auto-merge on green** — rejected: the human gate is a product rule.
- **Optimistic merge in arrival order** — rejected: semantic breaks reach
  `main`.
- **One file, one owner** — rejected: serializes the parallelism required.
- **Only the provider's queue** — rejected: not universal; no cross-demand
  view.

## Consequences

- The critic costs tokens; no routing saving applies to it.
- Merge is serialized per repository; queue position and forecast are shown
  in the cockpit.
- Re-verification per queue position costs compute (per-account cache).
- The syntax of the executable criteria is defined in the workflow spec, not
  here (`ROADMAP.md` P-8).

## Revisions

- 2026-09-04 — consolidated two records (rules before the PR; the merge
  queue) into one.
