# ADR-0013 — The `.proto` is the contract's source of truth

- **Status:** Accepted
- **Date:** 2026-08-30
- **Resolves:** F-12 (a tripled contract)

## Context

The contract was born tripled: a `types.ts` written by hand in the frontend, an empty
`openapi.yaml` with codegen running over nothing, and a future proto for the core. Three
sources, none authoritative — the *drift* started before there was a product.

## Decision

**One `.proto` per domain, versioned, is the only source.** From it are generated:

- the **core**'s server and types (Go);
- the **BFF**'s client (Python);
- **dop-cli**'s client;
- the **frontend**'s types (TS) and, when useful, the BFF's OpenAPI.

```
proto/dop/v1/  common · identity · resource · hierarchy · workflow
               demand · execution · delivery · knowledge · cost
```

Mandatory conventions:

1. **Server-side streaming** for everything live (`WatchDemand`, `StreamLogs`,
   `WatchAttention`); the BFF converts it into SSE for the browser.
2. **A `Ref` instead of a loose id** (`AccountRef{id}`) — a tenant is never an anonymous
   string.
3. **Every write RPC carries an `idempotency_key`** — with events and retries, that is a
   requirement, not a luxury.

   *Whose namespace the key lives in (added 2026-09-06).* `flows` made its
   `idempotency_key` UNIQUE across the whole table; `reaction_rules` deliberately did not,
   and scopes its uniqueness to `(account, key)`. The difference is not a preference. The
   key is supplied by the **client** and stored verbatim, so a table-wide namespace lets
   account B send a key account A already used, collide with a row B is not allowed to
   see, and get that collision handed back — as A's row if the conflict lookup forgets to
   filter by account, and as a `NotFound` about a rule B never wrote if it remembers.
   `flows` shipped the first of those once. Neither shape is right by default: scope the
   key to whatever owns the rows, and where a level has no owner — the platform's, which
   applies to everybody — give it a namespace of its own
   (`COALESCE(account_id, <nil uuid>)`) so its keys still collide with each other. The
   next table's author should reach that decision deliberately, rather than by copying
   whichever neighbour they opened first.
4. Compatibility validated in CI (`buf breaking`): a field changes neither its number nor its
   type.
5. **Who is calling and in which account travels in the metadata**, not in the body —
   `x-actor-id`, `x-account-id`, `x-actor-kind`, `x-session-id`, `x-request-id`, resolved by an
   interceptor before any use case. Context is a cross-cutting concern: in the body, every RPC
   would have to remember to check, and the one that forgot would become an isolation hole.

   *The debt was paid on 2026-09-02.* The request messages used to declare a `CallContext
   ctx = 1` from an earlier attempt, which the server **ignored**. A contract that declares a
   field with no effect teaches the wrong thing to whoever reads it and makes the client believe
   it is scoping the call when it is not — and it had already spread on its own into every new
   proto, the second factor's included. The field left the 12 protos, **number 1 is reserved** in
   every message that carried it, the `CallContext` message is gone from `common.proto`, and the
   BFF stopped building one. Two tests that asserted the field was in the body now assert the
   opposite, which is what stops it coming back.

## Alternatives considered

**OpenAPI as the source, with gRPC generated from it.** It inverts the dependency: the
internal contract (the core) would depend on the edge's format. Rejected.

**Contracts written by hand at both ends.** It is the current state, and it is the problem.

## Consequences

- ➕ One truth; the drift becomes a build error, not a discovery in production.
- ➕ The frontend stops inventing semantics (F-15): `types.ts` becomes a generated artifact.
- ➖ `buf` and codegen enter CI from day one.
- ➖ A contract change requires versioning discipline (additive by default).
