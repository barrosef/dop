# ADR-0017 — The `.proto` is the contract's source of truth

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
4. Compatibility validated in CI (`buf breaking`): a field changes neither its number nor its
   type.
5. **Who is calling and in which account travels in the metadata**, not in the body —
   `x-actor-id`, `x-account-id`, `x-request-id`, resolved by an interceptor before any use
   case. Context is a cross-cutting concern: in the body, every RPC would have to remember to
   check, and the one that forgot would become an isolation hole.

   *A recorded debt:* the request messages still declare a `CallContext ctx = 1` field from an
   earlier attempt. The server **ignores** that field — it authorizes only by the metadata. A
   contract that declares a field with no effect teaches the wrong thing to whoever reads it
   and makes the client believe it is scoping the call when it is not. The field leaves the
   protos (number 1 reserved, so as not to break compatibility) in a dedicated pass.

## Alternatives considered

**OpenAPI as the source, with gRPC generated from it.** It inverts the dependency: the
internal contract (the core) would depend on the edge's format. Rejected.

**Contracts written by hand at both ends.** It is the current state, and it is the problem.

## Consequences

- ➕ One truth; the drift becomes a build error, not a discovery in production.
- ➕ The frontend stops inventing semantics (F-15): `types.ts` becomes a generated artifact.
- ➖ `buf` and codegen enter CI from day one.
- ➖ A contract change requires versioning discipline (additive by default).
