# Architecture decisions — the DOP platform

A record of the structuring decisions, in the MADR format: context, decision, alternatives
considered and consequences.

## Before writing one, ask which ADR it belongs to

This index went from 15 documents to 30 in seven days, because the rule used to be *"an ADR
does not change once accepted — it is replaced"*: every refinement needed a new file. The rule
below replaces it. **One subject, one ADR.**

| The decision… | goes where |
|---|---|
| **refines, corrects or extends** one that exists | a **dated amendment inside it** — `**Where an artefact lives (added 2026-09-03):** …`. No new number |
| **changes** a decision other documents cite | a new number, and the old one says so **in its header**, with the link — not buried in the body |
| **opens a subject no ADR covers** | a new number |

A decision becomes an ADR at all when it is cited by more than one spec, when a real
alternative was rejected, or when somebody six months from now is going to ask "why like
this?". Everything narrower belongs where it is used: a port's guarantee in the port, an
operational recipe in the `dop-infra` spec.

If two ADRs describe the same subject, one of them is an amendment to the other.

## The decisions, by subject

### Foundations

| # | Title |
|---|---|
| [0001](0001-infrastructure-behind-ports.md) | Infrastructure behind ports with pluggable adapters — and, when an adapter cannot meet a guarantee, **the adapter pays** |
| [0016](0016-stack-go-core-python-bff.md) | A core in Go, a BFF in Python, and the boundary between them: **the BFF has no database** |
| [0017](0017-proto-as-source-of-truth.md) | The `.proto` is the contract's source of truth |

### Accounts, identity and access

| # | Title |
|---|---|
| [0002](0002-account-as-unit-of-ownership.md) | Tenancy: the account owns everything, and an organization proves itself by domain |
| [0026](0026-invite-without-token.md) | The invite has no secret: identity in place of a bearer |
| [0027](0027-second-factor-in-the-core.md) | The second factor is the platform's, with three verifiers |
| [0029](0029-the-core-verifies-its-callers.md) | The core verifies a signature; it does not believe a header |

### Resources, integrations and credentials

| # | Title |
|---|---|
| [0013](0013-resource-as-unit-of-sharing.md) | The resource as the account's unit of ownership and sharing |
| [0003](0003-organization-credential-human-authorship.md) | An organization credential to act, human authorship on the commit — **every rule about commits and push lives here** |

### State and events

| # | Title |
|---|---|
| [0006](0006-demand-as-event-log.md) | The demand is an event log; everything else is a projection |
| [0018](0018-postgres-persistence.md) | PostgreSQL as the single database, and the outbox that moves its events |

### The agents and their cost

| # | Title |
|---|---|
| [0010](0010-multi-agent-per-demand.md) | Multi-agent per demand: addressable threads and published findings |
| [0015](0015-project-orchestrator.md) | The project orchestrator: the techlead agent |
| [0022](0022-agent-provider-as-port.md) | The agent runtime: a port per vendor, running inside the core |
| [0011](0011-llm-cost-governance.md) | The LLM's cost: measuring it, capping it, routing it, and spending less *(the routing table is a draft)* |

### Knowledge and context

| # | Title |
|---|---|
| [0009](0009-context-as-subsystem.md) | Context is a subsystem: a knowledge base and a package per demand |
| [0028](0028-project-knowledge-as-a-git-repository.md) | The project's knowledge is a git repository, hosted by the platform |

### The work, its verification and its delivery

| # | Title |
|---|---|
| [0014](0014-dynamic-workflow.md) | A dynamic, typed and inheritable workflow |
| [0024](0024-sandbox-per-demand.md) | A microVM per demand, with a single shared worktree *(partly superseded — see its header)* |
| [0030](0030-verification-runs-from-source.md) | Verification builds from source in a runner, not from an image |
| [0007](0007-no-green-no-pr.md) | No green, no PR: native verification, and a merge queue per repository |

### Communication

| # | Title |
|---|---|
| [0025](0025-communication-trigger-and-channel.md) | Communication: the trigger and the channel are born together |

### Environment and infrastructure

| # | Title |
|---|---|
| [0020](0020-firebase-emulators-and-single-owner.md) | Firebase emulators in the local environment; Terraform as the single owner |

## Retired numbers

Consolidated on 2026-09-04, when seven documents were folded into the ADR that already owned
their subject. **A retired number is never reused** — an old reference (in git history, a
ticket, a commit message) must still resolve to the right place:

| Retired | Was | Now lives in |
|---|---|---|
| 0004 | Verifying an organization by domain | [0002](0002-account-as-unit-of-ownership.md) §3 |
| 0005 | A multi-tenant platform with organizations | [0002](0002-account-as-unit-of-ownership.md) §1 |
| 0008 | A merge queue per repository | [0007](0007-no-green-no-pr.md), rules 5–8 |
| 0012 | Token economy as an engineering discipline | [0011](0011-llm-cost-governance.md) §4–9 |
| 0019 | A transactional outbox + NATS JetStream | [0018](0018-postgres-persistence.md) §2–4 |
| 0021 | Read-after-write of a secret is not free on GCP | [0001](0001-infrastructure-behind-ports.md), "When an adapter cannot meet a guarantee" |
| 0023 | The AgentRuntime lives in the core | [0022](0022-agent-provider-as-port.md) §2 |

The operational half of 0020 (export on exit, the grace period, the environment-variable
bridge) moved to the [`dop-infra` spec](../superpowers/specs/dop-infra.md) §4.4, where somebody
operating the environment will actually look for it.
