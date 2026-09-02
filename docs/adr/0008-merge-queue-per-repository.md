# ADR-0008 — A merge queue per repository; a conflict is an agent's task

- **Status:** Accepted
- **Date:** 2026-08-29
- **Resolves:** F-4 — see `docs/analysis/2026-08-29-platform-critical-review.md`

## Context

Parallelism is an explicit requirement: SUOPTS-1501/1502/1503 at the same time,
"regardless of the repos overlapping". Three green PRs — each tested against the `main` of
when its branch was born. The first merge invalidates the other two: at best, a text
conflict; at worst, a **silent semantic break** (one PR removes the check the other assumed).
A PR's CI does not see it; production does. Agent fleets produce PRs at a rate that turns
that monthly accident into a daily occurrence.

## Decision

1. **A merge queue per repository, as a domain concept.** A green PR enters the queue; the
   queue reapplies each PR on top of the updated `main`, **re-runs the verification**
   (ADR-0007) and merges one at a time. Only what is green against the real state gets in.
2. **A conflict is an agent's task.** The rebase and the resolution are attempted by the
   demand's agent; a failure escalates to the human through the attention box, with the
   conflict's context. (The dop-cmd utility's flows — integration, preparation and conflict
   resolution — are mineable knowledge here; knowledge, not code.)
3. **Overlap is detected early.** The orchestrator sees which active demands touch the same
   files and flags the risk **before** the PR, not after.
4. **The provider's native queue when there is one** (GitHub's merge queue, GitLab's merge
   trains), consumed through the `GitProvider` port; DOP's queue orchestrates on top and
   covers the providers without the feature.

## Alternatives considered

**Optimistic merge** (merge in arrival order). Rejected: it is exactly the semantic-break
scenario.

**One file, one owner** (no file touched by two demands). Rejected: it kills the
parallelism that is a requirement — it becomes a queue in disguise.

**Only the provider's queue.** Rejected as the only route: not every provider has one, and
DOP needs the cross-demand view (item 3) that the provider does not have.

## Consequences

- ➕ A semantic break between parallel demands stops reaching `main`.
- ➖ A serialized merge per repository: delivery latency grows with the queue — visible in
  the cockpit, with the position and the forecast.
- ➖ Re-verification at each position in the queue costs compute; the per-account cache and
  preemptive suspension are the valves.
