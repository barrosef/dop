# ADR-0019 — A transactional outbox + NATS JetStream

- **Status:** Accepted
- **Date:** 2026-08-30
- **Realizes:** [ADR-0006](0006-demand-as-event-log.md) (the log) and the requirement of decoupled processes with atomic transactions

## Context

The product asked for: decoupled processes, strong resilience and **atomic event-based
transactions**, synchronous or asynchronous. The naive way — write to the database and then
publish to the broker — has a window in which the process dies between the two actions: the
state changed, nobody heard. A distributed commit (2PC) solves it and charges dearly in
complexity and availability.

## Decision

**A transactional outbox.** Every state change writes, **in the same Postgres transaction**,
the new state *and* the event into the append-only table. Commit ⇒ atomic by construction. A
**relay** reads the outbox and publishes to the broker, marking what was published —
at-least-once delivery, with no 2PC.

**The broker: NATS JetStream.** Light (one container), it runs identically on k3s and GKE,
persistent, with consumer groups, a DLQ and replay.

**Idempotent consumers** build the projections (the dossier, the timeline, the attention box,
the metrics, the cost) and react (the techlead wakes up, the launcher provisions, the index
regenerates). Retry with backoff; a poisoned message goes to the DLQ.

**Long processes are sagas** orchestrated by the core — the demand's finalization (commits →
PRs → the merge queue → conflicts → the dossier) is the canonical case: each step emits an
event, a failure compensates or escalates to the attention box, and the saga's state lives in
Postgres. The user perceives it as synchronous because the BFF pushes progress over SSE; the
execution is asynchronous and survives restarts.

## Alternatives considered

**Kafka.** A truck for our load; an operational and memory cost out of proportion.
**Google Pub/Sub.** Managed and good, but it ties us to GCP — it stays as a **second
adapter** of the `EventBus` port, for whoever prefers a managed one.
**Redis Streams.** Rejected: without JetStream's guarantees, and it would bring a service we
do not need yet (there is no cache requirement).
**Publishing straight from the code, with no outbox.** It is the loss window this ADR exists
to close.

## Consequences

- ➕ Real atomicity with no 2PC; never "I wrote but did not publish".
- ➕ Replay for free: the truth is the log, the projections are rebuildable.
- ➖ The relay's latency (polling) between the commit and the publication — acceptable;
  reducible with `LISTEN/NOTIFY` if it hurts.
- ➖ Idempotency becomes an obligation for every consumer, not a recommendation.
- ➖ One more piece to operate (NATS), mitigated by it being a single container.
