# ADR-0022 — The agent runtime: a port per vendor, running inside the core

- **Status:** Accepted
- **Date:** 2026-08-31 · **consolidated 2026-09-04**
- **Absorbs:** ADR-0023 (the AgentRuntime lives in the core) — two halves of one question,
  decided on the same day: what the runtime talks to, and where it runs. That number is
  **retired and never reused**.
- **Resolves:** the `AgentRuntime` coupled to a single vendor, and sitting on the wrong side of
  the credential boundary
- **Replaces:** [ADR-0016](0016-stack-go-core-python-bff.md)'s decision that *"the AgentRuntime
  lives in the BFF"*

## Context

### The vendor

When the `AgentRuntime` was specified — the piece that talks to the model — the initial
briefing said "write code that calls Anthropic's API". That was wrong, and the product owner
caught it: *"the platform has to think about isolation with multiple provider options,
including agent providers; for example Claude and Codex"*. It is ADR-0001 applied to the place
where it is easiest to forget, because the model vendor looks like "the product" and not like
"the infrastructure".

The data model already anticipated it, and nobody had connected the dots:

- **ADR-0013** defines an agent provider as an **integration of category `agent`** — a resource
  with a credential, shareable subject to authorization. Claude and Codex are two resources,
  not two versions of the code.
- The **cost router** (ADR-0011) already separates **policy** from **catalogue**:
  `routingTable` chooses the *class* (cheap/medium/strong) and `ModelCatalog` resolves the
  *concrete name* — "policy changes with telemetry, the catalogue changes when the vendor
  releases a model".

### The place

ADR-0016 put the `AgentRuntime` in the BFF: *"the core decides what; the BFF runs the
conversation with the model"*. The split looked clean. On implementing it, it charged its price:
the runtime needs the agent provider's credential, and a resource's credential lives in the
vault, behind `ports.SecretStore`, **in the core** — which **never returns a secret**, by
design, with a test guarding it. The ways out were all bad:

- **The BFF with its own access to the vault.** The implementation's initial recommendation,
  vetoed rightly by the product owner: *"the BFF is a very insecure layer, open to the
  internet"*. Compromising it would then hand over the agent credentials of ALL accounts. The
  session in which this was discussed had just found a **total authentication bypass** in that
  very layer — the argument is not hypothetical.
- **The core issuing an ephemeral token.** Elegant, and impossible today: an Anthropic API key
  is durable, there is no short-lived token to issue.
- **A separate service just for the runtime.** A third process, a third deployment, a third
  trust boundary — a high cost for the same problem.
- **Reading from an environment variable.** The stopgap that shipped: no per-account isolation,
  no cost attribution per credential, no revocation per resource.

## Decision

### 1. `AgentProvider` is a port, with one adapter per vendor

The runtime never sees an SDK type: it sends a conversation (a stable prefix + messages +
tools) and receives a response with usage (input, output, cache read, cache creation) and a
stop reason.

The adapter's choice is **per request**, not at boot — the difference that most affects the
wiring:

| | Chosen | Active at the same time |
|---|---|---|
| `SecretStore`, `EventBus`, `SandboxLauncher` | at boot, by configuration | one |
| **`AgentProvider`** | **per request, by the resource** | **several** |

It is the same nature as the task manager integrations: one project on Jira and another on
ClickUp coexist in the same account. Here, an account may have Claude and Codex, and the demand
chooses. The class comes from the router; the active adapter resolves the model's concrete
name — so the cost policy keeps holding for every vendor without knowing any of them.

### 2. The runtime runs in the CORE

The credential never crosses a network boundary: it is read from the vault and used in the same
process.

What the implementation revealed and weighed as much as the security: **the runtime was already
almost entirely the core's orchestration.** The six things it does in a turn — assembling
context, routing the model, recording consumption, posting a message, publishing a finding,
respecting the budget — are all core operations, done from outside over gRPC. It was on the
wrong side of the boundary.

Two modules existed **only because of the boundary** and disappear: `credentials.py` (115 lines
working around an inaccessible vault) and `catalog.py` (73 lines redoing the way back from the
model's name to its class, because the routing decision crossed the network losing the class).

The BFF is still the edge: it authenticates, aggregates and translates protocol. Running a turn
becomes a thin call to the core, and live follow-up still goes through the SSE that already
exists — the core emits an event, the BFF converts it.

## Alternatives considered

**A single adapter, and swap later.** It is what ADR-0001 exists to prevent: the first vendor
becomes the interface, and swapping later is a rewrite. That is exactly how the
`IdentityProvider` port spent months with one adapter — and hid an authentication bypass until
somebody wrote the second.

**An OpenAI compatibility layer.** Several vendors expose an "OpenAI-compatible" API, and it
would be tempting to treat that as the common denominator. Rejected: the compatibility covers
the simple case and leaks exactly where the platform needs precision — prefix caching, tool
format, token counting.

The four ways out of the credential problem, above, are the alternatives for §2; all rejected
for the reasons stated there.

## Consequences

- ➕ Swapping or adding a vendor is writing an adapter, not touching the runtime.
- ➕ The token economy (ADR-0011) becomes explicit per vendor, instead of assumed.
- ➕ The credential does not cross the network. Compromising the BFF does not expose an agent
  credential, and the BFF gets an invariant stronger than "it has no database": **it has no
  secret**.
- ➕ Six gRPC round trips per turn become in-process calls. The core is already isolated by a
  NetworkPolicy and already carries the vault; nothing new to protect.
- ➖ **Prefix-cache semantics are NOT the same between vendors**, and the saving depends on
  them. It is the most expensive divergence, and it has to be documented on the port.
- ➖ The tool-call format, the streaming events and the stop reasons also diverge; whatever
  cannot be met by all of them stays OUT of the port, explicitly.
- ➖ Two adapters and a contract suite from the start — the cost this platform has already paid
  three times.
- ➖ The provider adapters are rewritten in Go. ~600 lines; the design and the documented
  divergences survive — they change language, not design.
- ➖ The core starts making long external calls. Go handles that well, but the connection budget
  and the timeout become the core's concern.
- ➖ ADR-0016 is left with a replaced decision; the "the BFF has no database" boundary still
  holds, and gains its second half.
