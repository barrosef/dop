# ADR-0007 — No green, no PR: native verification before the human

- **Status:** Accepted
- **Date:** 2026-08-29
- **Resolves:** F-3 — see `docs/analysis/2026-08-29-platform-critical-review.md`
- **Refined by:** [ADR-0028](0028-project-knowledge-as-a-git-repository.md) — the `spec` artefact the executable criteria live in now has an address: `demand/<id>/spec.md` in the project's root repository

## Context

The 2026 research is conclusive: agents already close the loop up to the PR, and **the
flow's bottleneck has become human review capacity**. With no native verification, the
substrate's parallelism only moves the queue — from development to the reviewer's desk. The
PRD already fixes that a merge is a human decision; this ADR decides what happens
**before** the human is called.

## Decision

Four rules, in this order:

1. **Acceptance is born in the spec, executable.** Each demand carries criteria that a
   machine verifies in the sandbox: test suites (unit/AAA/e2e) and checks derived from the
   spec. A criterion that does not execute is not a criterion — it is a wish.
2. **The agent iterates to green.** No PR is opened with acceptance failing. A persistent
   failure becomes a block with a question to the human (the attention box), never a broken
   PR.
3. **A critic reviews before the human.** An independent instance, with a clean context and
   without the history of whoever implemented it: it receives diff + spec + evidence and
   issues a verdict. It is the first line of defence against rubber-stamping (F-5).
4. **The PR carries the evidence package**: the acceptance results, the test runs, the
   critic's verdict and links to the trace (ADR-0006). The human reviews the exception, not
   the rule.

## Alternatives considered

**Human-only review.** It is the market's default — and it is where the fleet drowns the
reviewer.

**Auto-merge on green.** Rejected: the PR's human gate is a non-goal fixed by the product,
and the critic does not replace responsibility.

## Consequences

- ➕ The parallelism gain reaches the merge whole, instead of dying in review.
- ➕ "Agent interruptions" become a quality metric for the spec (partly closes F-7).
- ➖ The exact format of the executable criteria belongs to SP-4's core (the spec's cycle);
  this ADR fixes the requirement, not the syntax.
- ➖ The critic costs tokens — a strong model, no saving here (ADR-0011).
