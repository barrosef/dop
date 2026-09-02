# The demand execution substrate

> **Status:** Approved for review · **Date:** 2026-08-29 · **Project:** the DOP platform
>
> **Answers:** where and how a demand executes — the sandbox, the life cycle, credentials,
> security and the ports that support it.
>
> **Does not answer:** the spec/demand's life cycle (SP-4's core, pending); verification and
> merge → [`verification-and-delivery.md`](verification-and-delivery.md); threads and
> attention → [`conversation-and-attention.md`](conversation-and-attention.md).

The base decisions: [ADR-0001](../../adr/0001-infrastructure-behind-ports.md),
[ADR-0003](../../adr/0003-organization-credential-human-authorship.md),
[ADR-0010](../../adr/0010-multi-agent-per-demand.md),
[ADR-0011](../../adr/0011-llm-cost-governance.md).

## 1. One demand, one sandbox

Each active demand gets a **sandbox**: a microVM containing the agent(s), the code workspace
and an internal Docker that brings up that demand's stack for testing and QA.

Kubernetes is the orchestration surface: **one namespace per demand** (`dop-<short-id>`, with
account/workspace/project/demand in labels — hierarchical identification is a label, not a
name). Isolation goes up from a container to a VM through one line:

| Environment | `runtimeClassName` | `isolationTier` |
|---|---|---|
| A cluster with KVM | `kata-fc` (Kata + Firecracker) | `hardware` |
| A cluster with gVisor/Edera | `gvisor` | `kernel-emulated` |
| With neither | a strict securityContext | `namespace` |

Two demands with the same repositories on different branches run with no interference: each
sandbox has its own workspace, its own stack and its own compose network.

## 2. The `ExecutionTarget` port

```
provision(demand, spec) → Sandbox
resume(id) · suspend(id) · destroy(id)
describe(id) → { state, isolationTier, endpoints }
```

- **`isolationTier` is declared, not presumed.** The client sees what it got.
- **`minIsolationTier` is the account's policy**: an unmet requirement = **a refusal with a
  message**, never a silent degradation.
- Adapters (two, per ADR-0001): **Kubernetes** — which serves both of the product's modes, SaaS
  on DOP's cluster and the customer's infrastructure, changing kubeconfig and limits, not the
  implementation — and **local** over the host's Docker, for developing the platform.
- The devbox runs as an **arbitrary non-root user** from the first image on — OKD/OpenShift
  refuse root through an SCC, and it is an image requirement, not a deployment one.

## 3. The life cycle

`active → suspended → destroyed`. With no agent work and no dev connected for N minutes, the
sandbox **suspends**: the pod dies, the workspace survives in a PVC. Resuming recreates the pod
over the existing workspace. Demands wait on humans for hours — an idle sandbox is what
separates real parallelism from a drowned machine.

A microVM snapshot/restore stays as an optimization to evaluate (Kata's support is limited);
the design does not depend on it.

## 4. Inside the sandbox

| | |
|---|---|
| **Agents** | 1 main + N subagents (ADR-0010), through the `AgentRuntime` port (§7) |
| **The workspace** | Worktrees of the demand's branches, in a PVC |
| **The internal Docker** | `docker compose -p <demand>`: its own network and DNS — `backend` resolves within that composition. It builds locally; no shared BuildKit/registry needed |
| **The context package** | Assembled at provisioning ([`context-and-knowledge.md`](context-and-knowledge.md)), read-only |
| **Caches** | A volume **per account** — never global: a cache shared between accounts is a side channel |

## 5. Access and credentials

- **The dev:** a terminal (a PTY, already existing in dop-app) and streaming logs;
  applications exposed through an ingress `<service>--<demand>.<domain>`.
- **Agent → platform:** always from the inside out, through the BFF. The sandbox does not need
  to be reachable for the agent to work.
- **Credentials:** nothing baked into an image, nothing persisted. The `SecretStore` resolves
  the account's credential and the sandbox receives a **short-lived derived token** (a 1h
  installation token for selected repositories — ADR-0003), as a projected volume.

## 6. The sandbox's security

The agent has the full triad — it reads untrusted content, it carries a credential, it has an
exit through git (F-10). Defence in layers, mandatory:

1. **An egress allowlist per sandbox**: only the demand's provider's git, the BFF and the
   model endpoints. Everything else denied by a NetworkPolicy.
2. **The card and the repository's content are untrusted input** — marked as such in every
   agent's context.
3. **Secret redaction in every output** of an agent and of a log.
4. **Runtime detection**: an anomalous action becomes an event (ADR-0006) and an alert.
5. A minimal, short token (§5) — the layer that already existed, kept.

## 7. The `AgentRuntime` port

ADR-0001 applied to the engine itself (F-14): the domain knows no agent SDK.

```
open(sandbox, card) → Session      // N sessions per sandbox (subagents)
send(session, msg) · cancel(session)
events(session) → stream           // actions, questions, cost (→ ADR-0006/0011)
```

The first adapter: the Claude Agent SDK; one adapter per agent provider of the account
(integrations with `category: agent` — Claude, Codex, Google Code Assist). The card (purpose,
tools, model, budget) comes from ADR-0010; the model, from the router (ADR-0011), **restricted
to the menu of the account's agent integrations**.

The port exposes the economy knobs (ADR-0012), filled in by the card: the **model**, the
**effort**, the **budget** (a task budget — the agent sees the ceiling and paces itself) and
the **cache policy** (a stable prefix layout; an operator's intervention through a `system`
message mid-conversation, never by editing the top of the prompt). The event stream reports
`cache_read`/`cache_creation` for ADR-0011's telemetry.

## 8. Risks

| # | |
|---|---|
| R-1 | Docker in a microVM with no cache pulls images on every demand — a per-account cache is a mandatory mitigation |
| R-2 | Resuming brings the compose stack back up: real latency perceived by the dev |
| R-3 | An ingress per demand multiplies objects/certificates in the controller |
| R-4 | The Kata `RuntimeClass` is missing in many distributions — the adapter detects it and applies the tier policy (§2), it never degrades in silence |
| R-5 | The egress allowlist breaks an unexpected legitimate dependency (e.g. a package registry) — the list is per project, editable, with audited changes |
