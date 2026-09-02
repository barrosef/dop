# ADR-0022 — An agent provider is a port, with an adapter per vendor

- **Status:** Accepted
- **Date:** 2026-08-31
- **Resolves:** the `AgentRuntime` coupled to a single vendor

## Context

When the `AgentRuntime` was specified — the piece that talks to the model — the initial
briefing said "write code that calls Anthropic's API". That was wrong, and the product owner
caught it: *"the platform has to think about isolation with multiple provider options,
including agent providers; for example Claude and Codex"*.

It is ADR-0001 applied to the place where it is easiest to forget, because the model vendor
looks like "the product" and not like "the infrastructure".

The data model already anticipated it, and nobody had connected the dots:

- **ADR-0013** defines an agent provider as an **integration of category `agent`** — a
  resource with a credential, shareable subject to authorization. Claude and Codex are two
  resources, not two versions of the code.
- The **cost router** (ADR-0011) already separates **policy** from **catalogue**:
  `routingTable` chooses the *class* (cheap/medium/strong) and `ModelCatalog` resolves the
  *concrete name*, with the comment saying why — "policy changes with telemetry, the
  catalogue changes when the vendor releases a model".

## Decision

**`AgentProvider` is a port, with one adapter per vendor.** The runtime never sees an SDK
type: it sends a conversation (a stable prefix + messages + tools) and receives a response
with usage (input, output, cache read, cache creation) and a stop reason.

The adapter's choice is **per request**, not at boot — and that is the difference that most
affects the wiring:

| | Chosen | Active at the same time |
|---|---|---|
| `SecretStore`, `EventBus`, `SandboxLauncher` | at boot, by configuration | one |
| **`AgentProvider`** | **per request, by the resource** | **several** |

It is the same nature as the task manager integrations: one project on Jira and another on
ClickUp coexist in the same account. Here, an account may have Claude and Codex, and the
demand chooses.

The class comes from the router; the active adapter resolves the model's concrete name. That
way the cost policy keeps holding for every vendor without knowing any of them.

## Alternatives considered

**A single adapter, and swap later.** It is what ADR-0001 exists to prevent: the first vendor
becomes the interface, and swapping later is a rewrite. That is exactly how the
`IdentityProvider` port spent months with one adapter — and hid an authentication bypass until
somebody wrote the second.

**An OpenAI compatibility layer.** Several vendors expose an "OpenAI-compatible" API, and it
would be tempting to treat that as the common denominator. Rejected: the compatibility covers
the simple case and leaks exactly where the platform needs precision — prefix caching, tool
format, token counting.

## Consequences

- ➕ Swapping or adding a vendor is writing an adapter, not touching the runtime.
- ➕ The token economy (ADR-0012) becomes explicit per vendor, instead of assumed.
- ➖ **Prefix-cache semantics are NOT the same between vendors**, and the saving depends on
  them. It is the most expensive divergence, and it has to be documented on the port.
- ➖ The tool-call format, the streaming events and the stop reasons also diverge; whatever
  cannot be met by all of them stays OUT of the port, explicitly.
- ➖ Two adapters and a contract suite from the start — which is the cost this platform has
  already paid three times.
