# ADR-0016 — The agent runtime: a port per vendor, running inside the core

- **Status:** Accepted
- **Date:** 2026-08-31
- **Relations:** applies ADR-0001; relies on ADR-0009 (an agent provider is an `integration` of category `agent`), ADR-0008 (policy vs catalogue); replaces ADR-0012's original placement of the runtime in the BFF

## Context

The runtime — the component that converses with a model — needs the model
provider's credential, which lives in the vault (`SecretStore`) inside the
core and is never returned by it. Accounts may hold several agent providers
at once.

## Decision

1. **`AgentProvider` is a port with one adapter per vendor** (Anthropic,
   OpenAI). The runtime sends a conversation — a stable prefix, messages,
   tools — and receives a response with usage (input, output, cache read,
   cache creation) and a stop reason. No SDK type crosses the port.
2. **The adapter is chosen per request, by the resource** (ADR-0001's second
   family); several are active at once. The router chooses the class
   (ADR-0008); the active adapter's catalogue resolves the concrete model.
3. **The runtime runs in the core.** The credential is read from the vault
   and used in the same process; it never crosses a network boundary. A
   turn's operations — assemble context, route, record usage, post a
   message, publish a finding, enforce the budget — are in-process calls.
4. **The BFF authenticates, aggregates and translates.** Running a turn is
   one call to the core; live follow-up is the existing SSE, fed by the
   core's events.
5. **What no vendor can guarantee stays out of the port** and is documented
   on it: prefix-cache semantics, tool-call format, streaming events, stop
   reasons.
6. Two adapters and one contract suite (ADR-0001).

## Alternatives considered

- **A single vendor, abstracted later** — rejected (ADR-0001).
- **An OpenAI-compatible API as the common denominator** — rejected: it
  diverges where precision is needed (caching, tools, token counting).
- **The BFF with vault access** — rejected: the BFF is exposed to the
  internet.
- **An ephemeral provider token issued by the core** — rejected: provider
  keys are durable.
- **A separate runtime service** — rejected: a third trust boundary.
- **The credential in an environment variable** — rejected: no per-account
  isolation, attribution or revocation.

## Consequences

- Adding a vendor is writing an adapter.
- The BFF's invariant is "no database, no secret".
- The core makes long outbound calls; connection budgets and timeouts are
  its concern.
- Prefix-cache behaviour differs per vendor; the saving of ADR-0008 §4 is
  per vendor.

## Revisions

- 2026-09-04 — consolidated two records (the port; the runtime's location)
  into one.
