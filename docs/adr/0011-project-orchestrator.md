# ADR-0011 — The project orchestrator: the techlead agent

- **Status:** Accepted
- **Date:** 2026-08-30
- **Relations:** gives ADR-0005 rule 7 an owner; relies on ADR-0004, ADR-0007, ADR-0008

## Context

Parallel demands in one project produce cross-cutting situations no single
demand's agent observes: file overlap between branches, a dependency
between demands, a behaviour change in one that breaks another's premise.

## Decision

1. **Every project has an orchestrator agent** (the techlead). It is
   activated when the project has two or more active demands and is idle
   otherwise. It runs on the platform, not in a demand's sandbox, and
   observes the event log, the branches' state and the demands' flows.
2. **It detects:** file overlap between active branches, dependencies
   between demands, behaviour interference (read semantically from specs
   and diffs).
3. **It plans before it asks.** On detection it produces options with a
   recommendation and opens an attention item; it never raises a raw alarm.
4. **A decision becomes a coordination directive**, an event visible in the
   threads involved. Initial vocabulary: sequencing with cherry-pick or
   rebase between branches; a preferred order in the merge queue; file
   partitioning; cross verification (one demand's acceptance over
   another's result). The vocabulary is extensible.
5. **A detected situation never pauses a demand.** The demand proceeds; when
   the directive's condition is met it applies the coordination and
   continues. A block exists only when the demand itself has exhausted what
   can be done, and is then its own attention item.
6. **Cost:** observation is event-driven and cheap; planning is routed as an
   investigation (ADR-0008 §3).

## Alternatives considered

- **Static rules only** (path diff, dependency graph) — kept as sensors;
  insufficient for behaviour interference.
- **Pausing demands at risk** — rejected: serializes required parallelism.
- **A human techlead** — rejected: the attention the platform exists to
  spare.

## Consequences

- Coordination directives are new inter-demand state, shown in the timeline
  and in both threads.
- The attention box receives decision items, not symptoms.
