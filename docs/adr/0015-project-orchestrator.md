# ADR-0015 — The project orchestrator: the techlead agent

- **Status:** Accepted
- **Date:** 2026-08-30
- **Complements:** [ADR-0008](0008-merge-queue-per-repository.md) (it gives the overlap
  detection an owner), [ADR-0010](0010-multi-agent-per-demand.md) (agents per demand),
  [ADR-0006](0006-demand-as-event-log.md) (the raw material for the observation)

## Context

With parallel demands in the same project, **cross-cutting** situations appear that no
demand's agent sees on its own: two demands touching the same files, one demand depending on
another's result, behaviour changes in which one interferes with the other. ADR-0008
foresaw "the orchestrator sees the overlap" without saying who it is. It now has a name and
a nature: **an agent**, not a cron of rules.

## Decision

1. **Every project has an orchestrator agent — the techlead of the demand agents.**
   Activated **dynamically**: it wakes up when the project has 2+ active demands; it sleeps
   otherwise. It lives on the platform, not in a demand's sandbox; it observes through the
   event log, the branches' state and the demands' flows.
2. **It observes the cross-cutting:** file overlap between active branches, dependency
   between demands, behaviour interference (a change that breaks another's premise).
3. **Autonomy first:** on identifying a cross-cutting situation, the techlead **plans
   solutions** and calls the **attention box** with a decision prompt — ready options, with a
   recommendation — never a raw alarm.
4. **A decision becomes a coordination directive.** The dev's choice is reflected in the
   demands as an instruction to the agents involved. The canonical example: "demand 1 depends
   on demand 0" → the decision: when 0 commits what 1 needs, 1 **cherry-picks** from 0's
   branch and carries on. The directive is an event (ADR-0006) and appears in the demands'
   threads.
5. **The golden rule: an identified cross-cutting situation NEVER pauses a demand.** Demand 1
   goes as far as it can; when the directive's condition is met (0 has committed), it applies
   the coordination (the cherry-pick is done) and continues. A block only exists if the demand
   itself exhausts what can be done without the condition — and then it is its own block,
   visible in the box.
6. **The initial vocabulary of directives:** sequencing with a cherry-pick/rebase between
   branches; a preferred order in the merge queue; file partitioning ("2 does not touch module
   X until 1 merges"); cross verification (running 1's acceptance over 0's result).
   Extensible — the techlead is the one who proposes, the vocabulary only names.

## Alternatives considered

**Static detection rules (a path diff + a declared dependency graph).** They stay as the
techlead's sensors, but are not enough alone: behaviour interference does not show up in a
path — it needs a semantic reading of the specs and the diffs.

**Pausing demands at risk until a decision.** Rejected with emphasis: it kills the
parallelism that is a requirement and turns detection (cheap) into a block (expensive). The
cost of carrying on and coordinating later is lower than the cost of stopping.

**A human techlead.** It is everybody's way today — and it is exactly the scarce attention
the platform exists to spare. The human decides; the techlead detects, plans and executes the
coordination.

## Consequences

- ➕ The requirement's parallelism ("SUOPTS-1501/02/03 at the same time, the same repo") gains
  the supervisor it lacked; F-4 closes entirely (a merge queue + upstream coordination).
- ➕ The attention box receives ready decision items, not symptoms.
- ➖ The techlead's model cost: observation is cheap (events/diffs), planning is expensive —
  routed as an investigation (ADR-0011); it wakes on an event, not by polling.
- ➖ A coordination directive is new state between demands — it has to appear in the Timeline
  and in both ends' threads, or it becomes invisible magic.
