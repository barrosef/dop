# ADR-0014 — PostgreSQL as the single database, and the outbox that moves its events

- **Status:** Accepted
- **Date:** 2026-08-30 · **consolidated 2026-09-04**
- **Absorbs:** the former ADR 0019 (a number retired by the 2026-09-17 renumbering) (a transactional outbox + NATS JetStream) — where the truth is stored
  and how it leaves the database is one subject. That number is **retired and never reused**.
- **Resolves:** F-16 (contradictory persistence signals)
- **Refines / realizes:** [ADR-0004](0004-demand-as-event-log.md) — the log, and the
  requirement of decoupled processes with atomic transactions

## Context

**What to store it in.** The product signalled "an adequate database, like Mongo for example"
in an early conversation. When the backend was designed, the workloads became clear, and they
are of three natures: relational (accounts × memberships × grants × projects), documental
(flows, cards, event payloads) and semantic (the knowledge's memories).

**How to get an event out of it.** The product asked for decoupled processes, strong resilience
and **atomic event-based transactions**, synchronous or asynchronous. The naive way — write to
the database and then publish to the broker — has a window in which the process dies between
the two actions: the state changed, nobody heard. A distributed commit (2PC) solves it and
charges dearly in complexity and availability.

## Decision

### 1. PostgreSQL for everything, with JSONB and pgvector covering the other two natures

- **Relational in the spine:** multi-tenant integrity is an FK and a constraint, not an
  application convention. Every domain table carries an `account_id`.
- **JSONB** for flows (ADR-0010), agent cards and event payloads — schema-free where it
  matters, with an index.
- **The event log** in an append-only table partitioned by month, with the outbox of §2.
- **pgvector** for the semantic search of the memories (ADR-0006) — **with no extra vector
  store**.
- **Projections** (the dossier, the timeline, the attention box) start as *materialized views*;
  they become tables fed by the worker only if the cost demands it.
- Portability: Cloud SQL on GCP, CloudNativePG on k3s — the same engine.

### 2. A transactional outbox

Every state change writes, **in the same Postgres transaction**, the new state *and* the event
into the append-only table. Commit ⇒ atomic by construction. A **relay** reads the outbox and
publishes to the broker, marking what was published — at-least-once delivery, with no 2PC.

### 3. The broker: NATS JetStream

Light (one container), it runs identically on k3s and GKE, persistent, with consumer groups, a
DLQ and replay.

**Idempotent consumers** build the projections (the dossier, the timeline, the attention box,
the metrics, the cost) and react (the techlead wakes up, the launcher provisions, the index
regenerates). Retry with backoff; a poisoned message goes to the DLQ.

> **Amendment, 2026-09-13.** This section described the DLQ as if it existed.
> It did not: on exhaustion the adapter called `Term()`, which discards, under
> a log line claiming the message had been saved. The queue, the classification
> and the terminal table were built by
> [the 2026-09-13 spec](../superpowers/specs/2026-09-13-event-context-and-dlq-design.md).
> The stream's 30-day retention was the only thing standing between an
> exhausted event and nothing at all.

### 4. Long processes are sagas

Orchestrated by the core — the demand's finalization (commits → PRs → the merge queue →
conflicts → the dossier) is the canonical case: each step emits an event, a failure compensates
or escalates to the attention box, and the saga's state lives in Postgres. The user perceives
it as synchronous because the BFF pushes progress over SSE; the execution is asynchronous and
survives restarts.

## Alternatives considered

**MongoDB.** Good for the documental, bad for the relational that dominates the domain;
multi-tenant integrity would become the application's responsibility — the wrong place.

**Postgres + a dedicated vector store** (Qdrant, an external pgvector). Rejected on YAGNI: one
more service to operate before there is volume to justify it.

**Postgres + Kafka as the log.** Rejected: the log lives in the database (the outbox); the
broker transports, it does not hold the truth. And Kafka on its own is a truck for our load —
an operational and memory cost out of proportion.

**Google Pub/Sub.** Managed and good, but it ties us to GCP — it stays as a **second adapter**
of the `EventBus` port, for whoever prefers a managed one.

**Redis Streams.** Rejected: without JetStream's guarantees, and it would bring a service we do
not need yet (there is no cache requirement).

**Publishing straight from the code, with no outbox.** It is the loss window §2 exists to close.

## Consequences

- ➕ One database: one operation, one backup, one expertise — and a real saving. A local
  transaction solves atomicity with no 2PC, and never "I wrote but did not publish".
- ➕ Replay for free: the truth is the log, the projections are rebuildable.
- ➖ The event load concentrated in the same database: it requires partitioning, retention and
  vigilance.
- ➖ Vector search in Postgres has a ceiling; when it arrives, it is extracted behind the same
  port.
- ➖ The relay's latency (polling) between the commit and the publication — acceptable;
  reducible with `LISTEN/NOTIFY` if it hurts.
- ➖ Idempotency becomes an obligation for every consumer, not a recommendation.
- ➖ One more piece to operate (NATS), mitigated by it being a single container.
