# Architecture decisions — the DOP platform

A record of the structuring decisions, in the MADR format: context, decision, alternatives
considered and consequences. An ADR **does not change** once accepted — it is replaced.

A decision becomes an ADR when it is cited by more than one spec, when a real alternative was
rejected, or when somebody six months from now is going to ask "why like this?".

| # | Title | Status |
|---|---|---|
| [0001](0001-infrastructure-behind-ports.md) | Infrastructure behind ports with pluggable adapters | Accepted |
| [0002](0002-account-as-unit-of-ownership.md) | The account as the single unit of ownership and isolation | Accepted |
| [0003](0003-organization-credential-human-authorship.md) | An organization credential to act, human authorship on the commit | Accepted |
| [0004](0004-organization-verification-by-domain.md) | Verifying an organization by domain, not by ownership | Accepted |
| [0005](0005-multi-tenant-platform.md) | A multi-tenant platform with organizations | Accepted |
| [0006](0006-demand-as-event-log.md) | The demand is an event log; everything else is a projection | Accepted |
| [0007](0007-no-green-no-pr.md) | No green, no PR: native verification before the human | Accepted |
| [0008](0008-merge-queue-per-repository.md) | A merge queue per repository; a conflict is an agent's task | Accepted |
| [0009](0009-context-as-subsystem.md) | Context is a subsystem: a knowledge base and a package per demand | Accepted |
| [0010](0010-multi-agent-per-demand.md) | Multi-agent per demand: addressable threads and published findings | Accepted |
| [0011](0011-llm-cost-governance.md) | LLM cost governance: firm measurement, routing in draft | **Draft** |
| [0012](0012-token-economy.md) | Token economy as an engineering discipline | Accepted |
| [0013](0013-resource-as-unit-of-sharing.md) | The resource as the account's unit of ownership and sharing | Accepted |
| [0014](0014-dynamic-workflow.md) | A dynamic, typed and inheritable workflow | Accepted |
| [0015](0015-project-orchestrator.md) | The project orchestrator: the techlead agent | Accepted |
| [0016](0016-stack-go-core-python-bff.md) | A core in Go, a BFF in Python, and the boundary between them | Accepted |
| [0017](0017-proto-as-source-of-truth.md) | The `.proto` is the contract's source of truth | Accepted |
| [0018](0018-postgres-persistence.md) | PostgreSQL as the single database, with pgvector | Accepted |
| [0019](0019-outbox-and-nats.md) | A transactional outbox + NATS JetStream | Accepted |
| [0020](0020-firebase-emulators-and-single-owner.md) | Firebase emulators in the local environment; Terraform as the single owner | Accepted |
| [0021](0021-read-after-write-of-a-secret.md) | Read-after-write of a secret is not free on GCP | Accepted |
| [0022](0022-agent-provider-as-port.md) | An agent provider is a port, with an adapter per vendor | Accepted |
| [0023](0023-agent-runtime-in-the-core.md) | The AgentRuntime lives in the CORE | Accepted |
| [0024](0024-sandbox-per-demand-and-ephemeral-verification.md) | A microVM per demand, a single worktree, verification in an ephemeral pod | Accepted |
| [0025](0025-communication-trigger-and-channel.md) | Communication: the trigger and the channel are born together | Accepted |
| [0026](0026-invite-without-token.md) | The invite has no secret: identity in place of a bearer | Accepted |
| [0027](0027-second-factor-in-the-core.md) | The second factor is the platform's, with three verifiers | Accepted |
