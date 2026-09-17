# Verification and delivery

> **Status:** Approved for review · **Date:** 2026-08-29 · **Project:** the DOP platform
>
> **Answers:** the code's path from the sandbox to `main` — acceptance, the critic, evidence,
> the PR and the merge queue.
>
> **Does not answer:** the format/syntax of the criteria in the spec (SP-4's core, pending);
> human review inside the provider (that is git's native gate, kept).

The base decisions: [ADR-0005](../../adr/0005-no-green-no-pr.md),
[ADR-0023](../../adr/0023-verification-runs-from-source.md),
[ADR-0005](../../adr/0005-no-green-no-pr.md),
[ADR-0003](../../adr/0003-organization-credential-human-authorship.md).

## 1. The path, end to end

```
the spec (executable criteria)
  → the agent iterates on the BENCH to green     [a persistent failure → the attention box]
  → a RUNNER verifies the commit from source     [clean environment, ADR-0023]
  → the critic reviews (a clean instance)        [rejected → back to the agent, with the opinion]
  → a PR with the evidence package               [the account's credential; author = the dev]
  → the repository's merge queue                 [rebase → re-verification → serial merge]
  → main                                         [an event → the index updates, the demand advances]
```

## 2. Acceptance

Criteria from the spec that a machine executes in a **runner** — an ephemeral environment that
pulls the COMMIT and builds the application from source ([`verification-runner.md`](verification-runner.md),
ADR-0023). Not on the bench: evidence produced where the agent worked speaks about the agent's
environment, with whatever it installed along the way, and not about a clean one.

The suites are the same (unit/AAA, e2e, integration); what changed is where they run and what
that makes the green mean. Each run's result is an event
(ADR-0004). ADR-0005's rule: **no PR opens with acceptance failing** — a persistent failure
becomes a block with a question, never a broken PR.

## 3. The critic

- An independent instance with a clean context (it does not inherit the conversation of
  whoever implemented it); a **strong** model, **maximum** effort — there is no saving on the
  brake (ADR-0008).
- It receives: the full diff, the spec, the acceptance results, the demand's findings.
- It issues a structured opinion: `approve | approve with reservations | reject (reasons)`. A
  rejection goes back to the agent with the opinion; an approval goes on to the PR with the
  opinion attached.

## 4. The PR and the evidence package

A fixed composition: a summary of the change and of the demand; **who asked** (the PR's body)
and **who ran it** (the commits' `author`) — ADR-0003; the acceptance and test results; the
critic's opinion; links to the demand's trace. The human reviewer gets an exception to read,
not archaeology.

## 5. The merge queue

States per repository: `queued → rebase → re-verification → merge` — one at a time.

- **The rebase and the conflict resolution are the demand's agent's task**; a failure escalates
  to the attention box with the conflict's context.
- **The re-verification runs the acceptance again** over the rebase's result — it is what
  catches the semantic break between parallel demands.
- **The provider's native queue** (GitHub's merge queue, GitLab's merge trains) is used when
  there is one, through `GitProvider`; DOP's queue orchestrates on top and covers the rest.
- **Overlap detection:** the **project's techlead** (ADR-0011) compares the files touched by
  the active demands, reads specs and diffs for behaviour interference, and proposes
  coordination directives in the attention box — without ever pausing a demand (the "carry on
  as far as you can" rule).
- The position in the queue and the forecast are visible in the cockpit.

## 6. Risks

| # | |
|---|---|
| R-1 | A long queue on a hot repository serializes delivery — overlap detection and per-account scheduling are the valves |
| R-2 | A complacent critic hands the problem back to the human — calibrate with F-7's metrics (PRs rejected after the critic) |
| R-3 | Repeated re-verification in a queue is the flow's biggest compute consumer — a per-account build cache is a prerequisite, not a luxury |
