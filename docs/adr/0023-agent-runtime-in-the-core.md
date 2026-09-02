# ADR-0023 — The AgentRuntime lives in the CORE

- **Status:** Accepted
- **Date:** 2026-08-31
- **Replaces:** [ADR-0016](0016-stack-go-core-python-bff.md)'s decision that *"the AgentRuntime lives in the BFF"*

## Context

ADR-0016 put the `AgentRuntime` in the BFF: *"the core decides what (flow, card, budget,
routing); the BFF runs the conversation with the model"*. The split looked clean — the
decision on one side, the execution on the other.

On implementing it, it charged its price.

The runtime needs the agent provider's credential. A resource's credential lives in the
vault, behind `ports.SecretStore`, **in the core** — and the core **never returns a secret**,
by design, with a test guarding it. The ways out were all bad:

- **The BFF with its own access to the vault.** It was the implementation's initial
  recommendation, and the product owner vetoed it rightly: *"the BFF is a very insecure layer,
  open to the internet"*. Compromising the BFF would then hand over the agent credentials of
  ALL accounts. The session in which this was discussed had just found a **total
  authentication bypass** in that very layer — the argument is not hypothetical.
- **The core issuing an ephemeral token.** Elegant, and impossible today: an Anthropic API key
  is durable, there is no short-lived token to issue.
- **A separate service just for the runtime.** A third process, a third deployment, a third
  trust boundary — a high cost for the same problem.
- **Reading from an environment variable.** It was the stopgap that shipped, and it has no
  per-account isolation, no cost attribution per credential and no revocation per resource.

## Decision

**The `AgentRuntime` moves to the core.** The credential never crosses a network boundary: it
is read from the vault and used in the same process.

What the implementation revealed and weighed as much as the security: **the runtime was
already almost entirely the core's orchestration.** The six things it does in a turn —
assembling context, routing the model, recording consumption, posting a message, publishing a
finding, respecting the budget — are all core operations, done from outside over gRPC. It was
on the wrong side of the boundary.

Two modules existed **only because of the boundary** and disappear:

- `credentials.py` — 115 lines working around an inaccessible vault;
- `catalog.py` — 73 lines redoing the way back from the model's name to its class, because the
  routing decision crossed the network losing the class.

The BFF is still the edge: it authenticates, aggregates and translates protocol. Running a
turn becomes a thin call to the core, and live follow-up still goes through the SSE that
already exists — the core emits an event, the BFF converts it.

The `AgentProvider` port and the divergences between vendors (ADR-0022) **do not change**:
they change language, not design. What was learned — double token counting, cache accounting
missing on OpenAI, the operator's channel, effort downgrading — is contract knowledge, and it
survives the rewrite.

## Consequences

- ➕ The credential does not cross the network. Compromising the BFF does not expose an agent
  credential.
- ➕ The BFF gets an invariant stronger than "it has no database": **it has no secret**.
- ➕ Six gRPC round trips per turn become in-process calls.
- ➕ The core is already isolated by a NetworkPolicy and already carries the vault; nothing new
  to protect.
- ➖ The provider adapters are rewritten in Go. ~600 lines; the design and the documented
  divergences survive.
- ➖ The core starts making long external calls. Go handles that well, but the connection
  budget and the timeout become the core's concern.
- ➖ ADR-0016 is left with a replaced decision; the "the BFF has no database" boundary still
  holds, and gains its second half.
