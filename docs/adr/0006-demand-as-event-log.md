# ADR-0006 — The demand is an event log; everything else is a projection

- **Status:** Accepted
- **Date:** 2026-08-29
- **Resolves:** F-8 (trace/replay), F-7 (telemetry), P-1 (auditing) — see `docs/analysis/2026-08-29-platform-critical-review.md`

## Context

Five distinct needs each ask for a record of what happened on a demand:

1. **Debugging** — reproducing, step by step, a demand that went wrong.
2. **Auditing** — in an organization, answering "who authorized this push, with which
   credential?" (it chains with ADR-0003).
3. **The dossier** — the requirements already ask for it to be "generated at runtime, stage
   by stage", not assembled at the end.
4. **Security** — forensics and detection when malicious content tries to divert the agent.
5. **Metrics** — human interventions, rework, time-to-green.

Building five mechanisms is writing the same data five times and watching them diverge.

## Decision

**Every action on a demand emits an immutable event**, in an append-only log per demand:
`{when, actor (human | agent | subagent), action, credential used (ref), summarized input,
result}`. The log is the demand's spine; **the dossier, the timeline, auditing, replay and
metrics are projections** of it — reads, never writes of their own.

A consequence for SP-3: the event log is a first-class citizen of persistence; the document
store serves projections, it does not replace it (closes F-16).

## Alternatives considered

**One store per consumer** (a dossier table + an audit trail + a metrics pipeline).
Rejected: a triple write, guaranteed divergence, and replay never arrives.

**An unstructured textual log.** Rejected: it is neither queryable nor projectable; auditing
in a multi-tenant system needs fields, not grep.

## Consequences

- ➕ One investment, five returns; P-1 leaves the pending list.
- ➕ The subagents' "findings" (ADR-0010) and the metering (ADR-0011) are just two more event
  types — no new mechanism.
- ➖ The discipline of emitting everywhere: an action with no event is a bug, not a detail.
- ➖ Volume: the log grows with the fleet; retention and compaction are an SP-3 decision.
