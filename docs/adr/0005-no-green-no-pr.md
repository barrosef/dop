# ADR-0005 — No green, no PR: native verification, and a merge queue per repository

- **Status:** Accepted
- **Date:** 2026-08-29 · **consolidated 2026-09-04**
- **Absorbs:** the former ADR 0008 (a number retired by the 2026-09-17 renumbering) (a merge queue per repository) — the same path from green to `main`,
  in one ADR. That number is **retired and never reused**.
- **Resolves:** F-3 and F-4 — see `docs/analysis/2026-08-29-platform-critical-review.md`
- **Refined by:** [ADR-0021](0021-project-knowledge-as-a-git-repository.md) — the `spec`
  artefact the executable criteria live in now has an address: `demand/<id>/spec.md` in the
  project's root repository. [ADR-0023](0023-verification-runs-from-source.md) — the
  verification runs in a runner, from source, not in the sandbox.

## Context

Two failures on the same path, and they are consecutive.

**Before the human.** The 2026 research is conclusive: agents already close the loop up to the
PR, and **the flow's bottleneck has become human review capacity**. With no native
verification, the executor's parallelism only moves the queue — from development to the
reviewer's desk. The PRD already fixes that a merge is a human decision; this ADR decides what
happens before the human is called.

**After the green.** Parallelism is an explicit requirement: SUOPTS-1501/1502/1503 at the same
time, "regardless of the repos overlapping". Three green PRs — each tested against the `main`
of when its branch was born. The first merge invalidates the other two: at best, a text
conflict; at worst, a **silent semantic break** (one PR removes the check the other assumed).
A PR's CI does not see it; production does. Agent fleets produce PRs at a rate that turns that
monthly accident into a daily occurrence.

## Decision

### Before the PR — four rules, in this order

1. **Acceptance is born in the spec, executable.** Each demand carries criteria that a machine
   verifies: test suites (unit/AAA/e2e) and checks derived from the spec. A criterion that
   does not execute is not a criterion — it is a wish.
2. **The agent iterates to green.** No PR is opened with acceptance failing. A persistent
   failure becomes a block with a question to the human (the attention box), never a broken PR.
3. **A critic reviews before the human.** An independent instance, with a clean context and
   without the history of whoever implemented it: it receives diff + spec + evidence and issues
   a verdict. It is the first line of defence against rubber-stamping (F-5).
4. **The PR carries the evidence package**: the acceptance results, the test runs, the critic's
   verdict and links to the trace (ADR-0004). The human reviews the exception, not the rule.

### After the green — the queue

5. **A merge queue per repository, as a domain concept.** A green PR enters the queue; the
   queue reapplies each PR on top of the updated `main`, **re-runs the verification** and
   merges one at a time. Only what is green against the real state gets in.
6. **A conflict is an agent's task.** The rebase and the resolution are attempted by the
   demand's agent; a failure escalates to the human through the attention box, with the
   conflict's context. (The dop-cmd utility's flows — integration, preparation and conflict
   resolution — are mineable knowledge here; knowledge, not code.)
7. **Overlap is detected early.** The orchestrator ([ADR-0011](0011-project-orchestrator.md))
   sees which active demands touch the same files and flags the risk **before** the PR, not
   after.
8. **The provider's native queue when there is one** (GitHub's merge queue, GitLab's merge
   trains), consumed through the `GitProvider` port; DOP's queue orchestrates on top and covers
   the providers without the feature.

## Alternatives considered

**Human-only review.** It is the market's default — and it is where the fleet drowns the
reviewer.

**Auto-merge on green.** Rejected: the PR's human gate is a non-goal fixed by the product, and
the critic does not replace responsibility.

**Optimistic merge** (merge in arrival order). Rejected: it is exactly the semantic-break
scenario.

**One file, one owner** (no file touched by two demands). Rejected: it kills the parallelism
that is a requirement — it becomes a queue in disguise.

**Only the provider's queue.** Rejected as the only route: not every provider has one, and DOP
needs the cross-demand view (rule 7) that the provider does not have.

## Consequences

- ➕ The parallelism gain reaches the merge whole, instead of dying in review.
- ➕ A semantic break between parallel demands stops reaching `main`.
- ➕ "Agent interruptions" become a quality metric for the spec (partly closes F-7).
- ➖ The exact format of the executable criteria belongs to SP-4's core (the spec's cycle); this
  ADR fixes the requirement, not the syntax.
- ➖ The critic costs tokens — a strong model, no saving here (ADR-0008).
- ➖ A serialized merge per repository: delivery latency grows with the queue — visible in the
  cockpit, with the position and the forecast.
- ➖ Re-verification at each position in the queue costs compute; the per-account cache and
  preemptive suspension are the valves.
