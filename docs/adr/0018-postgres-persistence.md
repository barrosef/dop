# ADR-0018 — PostgreSQL as the single database, with pgvector

- **Status:** Accepted
- **Date:** 2026-08-30
- **Resolves:** F-16 (contradictory persistence signals) · **Refines:** [ADR-0006](0006-demand-as-event-log.md)

## Context

The product signalled "an adequate database, like Mongo for example" in an early
conversation. When the backend was designed, the workloads became clear, and they are of
three natures: relational (accounts × memberships × grants × projects), documental (flows,
cards, event payloads) and semantic (the knowledge's memories).

## Decision

**PostgreSQL for everything**, with JSONB and pgvector covering the other two natures.

- **Relational in the spine:** multi-tenant integrity is an FK and a constraint, not an
  application convention. Every domain table carries an `account_id`.
- **JSONB** for flows (ADR-0014), agent cards and event payloads — schema-free where it
  matters, with an index.
- **The event log** in an append-only table partitioned by month, with an **outbox**
  ([ADR-0019](0019-outbox-and-nats.md)).
- **pgvector** for the semantic search of the memories (ADR-0009) — **with no extra vector
  store**.
- **Projections** (the dossier, the timeline, the attention box) start as *materialized
  views*; they become tables fed by the worker only if the cost demands it.
- Portability: Cloud SQL on GCP, CloudNativePG on k3s — the same engine.

## Alternatives considered

**MongoDB.** Good for the documental, bad for the relational that dominates the domain;
multi-tenant integrity would become the application's responsibility — the wrong place.

**Postgres + a dedicated vector store** (Qdrant, an external pgvector). Rejected on YAGNI:
one more service to operate before there is volume to justify it.

**Postgres + Kafka as the log.** Rejected: the log lives in the database (the outbox); the
broker transports, it does not hold the truth.

## Consequences

- ➕ One database: one operation, one backup, one expertise — and a real saving.
- ➕ A local transaction solves atomicity with no 2PC.
- ➖ The event load concentrated in the same database: it requires partitioning, retention and
  vigilance.
- ➖ Vector search in Postgres has a ceiling; when it arrives, it is extracted behind the same
  port.
