# ADR-0004 — The demand is an event log; everything else is a projection

- **Status:** Accepted
- **Date:** 2026-08-29
- **Relations:** realized by ADR-0014 (persistence and the outbox); relied on by ADR-0007, ADR-0008, ADR-0011, ADR-0018, ADR-0021, ADR-0022

## Context

Debugging, auditing, the dossier, security forensics and metrics each need a
record of what happened on a demand. One record serves all five.

## Decision

1. **Every write in the core emits an immutable event** into an append-only
   log, in the same transaction as the state change (ADR-0014).
2. **The event envelope** (`ports.Event`):

   | field | content |
   |---|---|
   | `id` | the event's UUID; also the broker message id |
   | `account_id` | the owning account |
   | `aggregate`, `aggregate_id` | the entity the event belongs to |
   | `aggregate_key` | a human-readable key of the aggregate (`account-created`, `pr-delivered`) |
   | `type` | the event type, e.g. `dop.identity.invite.created` |
   | `payload` | JSON, type-specific |
   | `occurred_at` | timestamp |
   | `actor_kind`, `actor_id` | `user` / `agent` / `platform`, and who |
   | `request_id`, `session_id`, `caller` | the call's context |

3. **The dossier, the timeline, auditing, replay, metrics and the attention
   box are projections** of the log: reads, never writes of their own.
4. **An action with no event is a defect.**

## Alternatives considered

- **One store per consumer** (dossier table, audit trail, metrics pipeline) —
  rejected: multiple writes, divergence, no replay.
- **An unstructured text log** — rejected: not queryable per tenant.

## Consequences

- Findings (ADR-0007), cost metering (ADR-0008) and notifications
  (ADR-0018) are event types, not mechanisms.
- The log's volume is the persistence layer's concern: partitioning and
  retention (ADR-0014).

## Revisions

- 2026-09-13 — the envelope gained `aggregate_key`, `actor_kind`, `actor_id`,
  `request_id`, `session_id`, `caller`.
