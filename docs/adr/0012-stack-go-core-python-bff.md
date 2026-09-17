# ADR-0012 — A core in Go, a BFF in Python, and the boundary between them

- **Status:** Accepted
- **Date:** 2026-08-30
- **Refines:** [ADR-0001](0001-infrastructure-behind-ports.md) · **Resolves:** F-14 (the agent engine behind a port)

## Context

The platform has two very different natures of work: **domain, state and transactions**
(identity, resources, flows, demands, delivery, cost) and **conversation with AI models**
(long sessions, token streaming, tools, embeddings). Forcing both into the same language
charges somewhere: gRPC and concurrency in Python are uncomfortable; the agent and embedding
ecosystem in Go is shallow.

## Decision

**`dop-core` in Go. `dop-api` (the BFF) in Python.**

| | dop-core (Go) | dop-api (Python) |
|---|---|---|
| Responsibility | domain, state, transactions, events, orchestration | protocol, agent session, conversation with models |
| It speaks | gRPC (server) · Postgres · NATS · the k8s API | REST+SSE (the app) · gRPC (the CLI, the sandbox) · **the core's gRPC client** |
| Modes | `serve` · `worker` · `sched` · `launcher` (one binary) | one ASGI process |

**The boundary, in one rule: the BFF has no database.** No connection from Python to
Postgres — not even "just for a quick query". Two owners of the schema is how the boundary
dies. When the BFF needs to record something, it **calls the core**, which writes state and
event in the same transaction.

**~~The `AgentRuntime` lives in the BFF~~ — REPLACED by [ADR-0016](0016-agent-provider-as-port.md): the runtime moved to the core, because the provider's credential cannot reach the layer exposed to the internet.** ~~The `AgentRuntime` lives in the BFF~~ (the execution spec's ADR-0011 §7): the core decides *what*
(flow, card, budget, routing — ADR-0008); the BFF runs the conversation with the model and
returns events to the core. The sandbox talks **only to the BFF**, which keeps the egress
allowlist minimal (F-10).

## Alternatives considered

**Everything in Python.** Continuity with the existing repertoire and a single language.
Rejected for the core: the core is a gRPC server with event consumers and a Kubernetes
daemon — work at which Go is materially better (a single binary, instant startup on
scale-to-zero, cheap concurrency).

**Everything in Go.** Coherent on the backend, but the BFF would lose the AI ecosystem (the
agent SDK, embeddings, tokenization) — which is precisely the product's core.

**TypeScript across the whole backend** (one language with the frontend). Rejected for the
same reason: the most complete agent and embedding libraries are Python.

## Consequences

- ➕ Each piece in the language in which its work is natural.
- ➕ The "the core owns the state" boundary forces a clean architecture by construction.
- ➕ The sandbox has a single interlocutor (the BFF) — a smaller security surface.
- ➖ Two languages: two toolchains, two lint/test setups, two image pipelines.
- ➖ Every call from the BFF to the core is network — it requires a deadline, a retry and
  idempotency (the proto carries an `idempotency_key` on every write).
- ➖ Types duplicated at both ends, mitigated by generating both from the same proto
  ([ADR-0013](0013-proto-as-source-of-truth.md)).
