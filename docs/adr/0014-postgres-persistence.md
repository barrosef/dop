# ADR-0014 — PostgreSQL as the single database, and the outbox that moves its events

- **Status:** Accepted
- **Date:** 2026-08-30
- **Relations:** realizes ADR-0004; relied on by ADR-0018, ADR-0019

## Context

Three natures of data — relational (accounts, memberships, grants,
projects), documental (flows, cards, event payloads), semantic (memories) —
and the requirement that a state change and its event are atomic and that
processes are decoupled.

## Decision

### 1. One database

- **PostgreSQL** for everything; the same engine in both environments
  (Cloud SQL / a VM on GCP; CloudNativePG on a cluster).
- Relational integrity in the schema: every domain table carries
  `account_id`; multi-tenant constraints are foreign keys and constraints.
- **JSONB** for flows, agent cards and event payloads, with indexes.
- **The event log** is an append-only table partitioned by month.
- **pgvector** for the memories' semantic search; no separate vector store.
- **Projections** (dossier, timeline, attention box) start as materialized
  views and become worker-fed tables when cost requires.

### 2. Transactional outbox

Every state change writes the new state and the event into the outbox in
the same transaction. A relay reads the outbox and publishes to the broker,
marking each row as published: at-least-once delivery, no two-phase commit.

### 3. Broker and consumers — NATS JetStream

- One stream; subjects `dop.>` for events and `dlq.>` for dead letters. The
  message id is the event id (broker-side deduplication).
- Consumers are idempotent and build projections or react (`timeline`,
  `attention`, `notification`, `dlq`).
- **Redelivery:** `MaxDeliver = 5` with backoff `1s, 5s, 15s, 1min`.
- **Dead letters:** an exhausted delivery is published to `dlq.event` as a
  `DeadLetter{event, consumer, attempts[], classification, first_failed_at,
  last_failed_at}` carrying the full event envelope; the message id is
  `<event id>:<consumer>`.
- **The DLQ consumer** re-runs the same handler up to 3 more times, then
  terminates the message; every attempt is recorded.
- **Classification** of a failure is `recoverable | irrecoverable |
  unknown`, seeded from the error kind and learned per error signature: a
  signature that exhausts every retry twice is promoted to irrecoverable; a
  later success demotes it unless a human set the mark.
- **Error ledger:** `event_errors`, unique on `(event_id, consumer)`, holds
  the attempt history, broker attempts, classification and `last_success_at`.

### 4. Long processes are sagas

Orchestrated by the core (a demand's finalization: commits → PRs → merge
queue → conflicts → dossier); each step is an event; failures compensate or
escalate to the attention box; saga state lives in Postgres. Progress reaches
the cockpit over SSE.

## Alternatives considered

- **MongoDB** — rejected: relational integrity would move to the
  application.
- **A dedicated vector store** — rejected until volume requires it.
- **Kafka as the log** — rejected: the log is the database; the broker
  transports.
- **Google Pub/Sub** — a second `EventBus` adapter, not the default.
- **Redis Streams** — rejected: weaker guarantees, an extra service.
- **Publishing without an outbox** — rejected: loses events on failure
  between write and publish.

## Consequences

- One database to operate, back up and understand.
- Partitioning and retention of the event table are required.
- Every consumer must be idempotent.
- The relay's polling adds latency between commit and publication
  (`LISTEN/NOTIFY` if needed).

## Revisions

- 2026-09-04 — consolidated two records (the database; the outbox and
  broker) into one.
- 2026-09-13 — §3: dead letters, the DLQ consumer, failure classification
  and the error ledger, as built.
