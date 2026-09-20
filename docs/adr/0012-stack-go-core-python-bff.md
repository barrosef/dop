# ADR-0012 — A core in Go, a BFF in Python, and the boundary between them

- **Status:** Accepted
- **Date:** 2026-08-30
- **Relations:** refines ADR-0001; the agent runtime's location is decided by ADR-0016; the contract by ADR-0013; caller verification by ADR-0022

## Context

Two kinds of work: domain, state, transactions and orchestration (a gRPC
server, event consumers, a Kubernetes daemon); and protocol translation for
the cockpit and the CLI.

## Decision

1. **`dop-core` in Go; `dop-api` (the BFF) in Python.**

   | | dop-core | dop-api |
   |---|---|---|
   | responsibility | domain, state, transactions, events, orchestration, the agent runtime (ADR-0016) | authentication of the person, protocol translation, aggregation |
   | speaks | gRPC (server); Postgres; NATS; the Kubernetes API; model provider APIs | REST + SSE (the cockpit); gRPC (the CLI); gRPC client of the core |
   | processes | one binary: `serve`, `worker`, `sched`, `launcher` | one ASGI process |

2. **The BFF has no database and no secret.** No connection from the BFF to
   Postgres; no credential in the BFF's process or configuration. A write
   is a call to the core, which persists state and event in one transaction.
3. **The sandbox talks only to the BFF** (egress allowlist) and to the
   platform's git server (ADR-0021).
4. **Every BFF → core call carries a deadline, a retry policy and an
   `idempotency_key` on writes** (ADR-0013).

## Alternatives considered

- **Everything in Python** — rejected for the core: gRPC server, consumers
  and a daemon favour Go (single binary, fast start on scale-to-zero).
- **Everything in Go** — rejected for the edge: the Python ecosystem for
  agent SDKs and embeddings.
- **TypeScript across the backend** — rejected: same reason.

## Consequences

- Two toolchains, two test and lint setups, two image pipelines.
- Types exist at both ends, generated from the same `.proto` (ADR-0013).

## Revisions

- 2026-08-31 — the agent runtime moved from the BFF to the core (ADR-0016);
  "no secret" added to decision 2.
