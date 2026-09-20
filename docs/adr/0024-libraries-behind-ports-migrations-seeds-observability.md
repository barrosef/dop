# ADR-0024 — Infrastructure libraries behind ports, not an application framework; migrations, seeds and observability are three of them

- **Status:** Accepted
- **Date:** 2026-09-20
- **Relations:** realizes ADR-0001 and ADR-0012; extends ADR-0014; relied on by nothing yet

## Context

The core is Go over the standard library and `grpc-go`, with every piece of
infrastructure behind a port the domain declares (ADR-0001). Neither ADR-0001
nor ADR-0012 says whether the adapters themselves should be written over an
application framework (GoFr, Beego and the like) or over libraries chosen per
concern. Three concerns were found uncovered while shipping the onboarding
journey: migrations were applied by hand (`kubectl cp` + `psql` locally, an SSH
session on QA) with no record of what had run; there was no way to load data
into an environment other than a migration; and the only observability was a
structured log with a request id.

## Decision

### 1. No application framework in the core

The core stays on the standard library and `grpc-go`. Each infrastructure
concern enters as a **dedicated library behind the port that names it**, with
a contract suite, never as a framework that owns the process's lifecycle,
container or configuration. The reason is ADR-0001's: a framework's vocabulary
crosses the port; a library's stays in the adapter. The question reopens only
if the core ever serves HTTP itself — today HTTP is the BFF's (ADR-0012).

### 2. Migrations are applied by the binary, and recorded

- `migrations/*.sql` are embedded in `dop-core` and applied with
  [goose](https://github.com/pressly/goose) as a library; the files keep their
  `-- +goose Up` / `-- +goose Down` form. Version state lives in
  `goose_db_version`.
- `dop-core migrate up` applies what is missing; `migrate status` lists;
  `migrate baseline <version>` records versions up to `<version>` as applied
  without running them — the one-time bootstrap of a database migrated by hand.
- **The worker runs `migrate up` at start, before consuming.** It is the one
  single-instance process in every environment. `serve` never migrates; it
  **refuses to start on a schema older than the binary knows** and retries
  for a bounded time, so a deploy that reaches Cloud Run before the worker has
  migrated waits instead of failing on a missing column.
- A migration carries the schema and the **reference data the schema cannot
  exist without** (the platform flow of `0005`). Nothing else.
- Every migration has a `Down`; numbers are contiguous; the architecture
  test enforces both.

### 3. Seeds load data; they are idempotent and separate

- `seed/*.sql` are embedded and applied with `dop-core seed`, in file order.
  A seed is **idempotent by contract** (`INSERT … ON CONFLICT DO UPDATE`); there
  is no seed version table, and re-running is the way to edit.
- `seed/` holds data every environment needs (the plan and provider
  catalogues). `seed/<profile>/` holds data for one kind of environment and
  runs only when `DOP_SEED_PROFILE=<profile>` (`local`: sample accounts and
  flows for development). Production runs the root seeds and no profile.
- The worker runs `seed` right after `migrate up`. Reference data therefore
  never needs a migration to change: edit the file, redeploy.

### 4. Observability, in three phases

**Phase 1 — logs and traces (now).**

- Logs stay structured JSON (`log/slog` in the core, the JSON logger in the
  BFF), and every line carries `trace_id` and `span_id` when a span is active.
- Traces use OpenTelemetry. The core instruments the gRPC server and client
  (`otelgrpc`), Postgres (`pgx` query tracer), and NATS — a publish injects the
  W3C `traceparent` into the message headers, a consumer continues the trace
  from it, so one trace crosses the outbox. The BFF instruments FastAPI, the
  gRPC client to the core and its own gRPC server; `x-request-id` stays as the
  human-readable correlation and is written onto the span.
- The exporter is configuration: `OTEL_EXPORTER_OTLP_ENDPOINT` for OTLP;
  `TRACE_BACKEND=gcp` for Cloud Trace on GCP; unset means no export and no
  cost. The local environment ships Jaeger; QA ships to Cloud Trace.
- Sampling: everything locally; on QA a parent-based ratio, configurable.

**Phase 2 — metrics.** RED per RPC (rate, errors, duration), consumer lag and
redelivery counts per subject, dead-letter counts by classification, outbox
depth, sandbox counts per tier. OpenTelemetry metrics, exported the same way.

**Phase 3 — SLOs and alerts.** Availability and latency per surface, defined
on the phase-2 metrics; alerts on burn rate. Not before phase 2 has data.

## Alternatives considered

- **An application framework in the adapter layer (GoFr, Beego)** — rejected.
  It would buy migrations and observability, both available as libraries,
  and would not cover what the core actually has (durable NATS consumers with
  dead letters, a vault, sandboxes, git providers), so it would own the
  lifecycle of a process whose adapters mostly live outside it.
- **The core migrating at `serve` start** — rejected: several instances on
  Cloud Run racing the same migration; goose locks, but a lock is not a
  design.
- **An ORM's auto-migration** — rejected with ADR-0014: the schema owns its
  SQL file, versioned and reviewed.
- **Seeds inside migrations** — rejected after being done once (`0027`): it
  puts a text edit behind a schema version and makes "re-run to edit"
  impossible.
- **Vendor tracing SDKs** — rejected: OpenTelemetry is the port; the vendor is
  the exporter.

## Consequences

- `make migrate` becomes `dop-core migrate up` against the local database;
  QA's data VM runs `migrate up && seed` before the worker; the first deploy
  after this ADR runs `migrate baseline 27` once on every existing database.
- `serve` gains a schema-version check at boot.
- A migration without `Down`, or with a gap in numbering, fails `make test`.
- The trace context crosses BFF → core → outbox → consumer; a slow request is
  one trace, not four logs to correlate by hand.
- Phases 2 and 3 are recorded here so nobody re-decides the vendor when they
  arrive.

## Revisions

- 2026-09-20 — accepted; phase 1 of observability, migrations and seeds
  implemented with it.
