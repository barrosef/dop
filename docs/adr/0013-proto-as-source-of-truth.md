# ADR-0013 — The `.proto` is the contract's source of truth

- **Status:** Accepted
- **Date:** 2026-08-30
- **Relations:** relies on ADR-0012; refined by ADR-0022 (the metadata is verified)

## Context

The contract between the core, the BFF, the CLI and the cockpit has one
source, from which every client and server is generated.

## Decision

1. **One `.proto` per domain, versioned** (`proto/dop/v1/`: `common`,
   `identity`, `resource`, `hierarchy`, `workflow`, `demand`, `execution`,
   `delivery`, `knowledge`, `cost`, `secondfactor`, …). Generated from it:
   the core's server and types (Go), the BFF's client (Python), the CLI's
   client, and — through the BFF's OpenAPI document — the cockpit's hooks
   and schemas (Orval). Generated code is never hand-edited.
2. **Live data is server-side streaming** (`WatchDemand`, `StreamLogs`,
   `WatchAttention`); the BFF converts it to SSE.
3. **Identifiers travel as typed references** (`AccountRef{id}`), never as
   loose strings.
4. **Every write RPC carries an `idempotency_key`**, supplied by the client
   and stored verbatim. Its uniqueness is scoped to the owner of the rows
   (`(account_id, key)`); platform-level rows with no account use a
   namespace of their own (`COALESCE(account_id, <nil uuid>)`). A table-wide
   namespace is not used.
5. **Who is calling, and in which account, travels in the call metadata**
   (`x-actor-id`, `x-account-id`, `x-actor-kind`, `x-session-id`,
   `x-request-id`), resolved by an interceptor before any use case, and
   verified per ADR-0022. Request messages carry no context field; field
   number 1 is reserved in every message that once did.
6. **Compatibility is enforced in CI** (`buf breaking`): a field never
   changes its number or type; changes are additive.

## Alternatives considered

- **OpenAPI as the source, gRPC generated from it** — rejected: the core's
  contract would depend on the edge's format.
- **Hand-written contracts at each end** — rejected: drift.

## Consequences

- `buf` and code generation run in CI from day one.
- A contract change is a versioned, additive change.

## Revisions

- 2026-09-02 — decision 5: the `CallContext` body field removed from all
  protos; number 1 reserved.
- 2026-09-06 — decision 4: the idempotency key's namespace.
