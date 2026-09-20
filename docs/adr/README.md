# Architecture decisions — the DOP platform

A record of the structuring decisions, in the MADR format: context, decision, alternatives
considered and consequences.

## What an ADR is here

An ADR **fixes a decision and describes the resulting architecture
technically**. It does not tell how the decision was reached, what was found
along the way, or what earlier drafts said — that story is published on the
site (`dop-t.com/decisions`) and kept in git history. Every ADR has the same
shape:

| section | holds |
|---|---|
| header | status, date, and **relations** to other ADRs (refines, refined by, relies on, supersedes, superseded by) |
| Context | the requirement or constraint, in a few lines |
| Decision | numbered statements with exact names, values and shapes (types, tables, env vars, limits) |
| Alternatives considered | one line each: the option, and why it is not the decision |
| Consequences | what the decision costs or obliges, technically |
| Revisions | one dated line per change to the decision text — no narrative |

**One subject, one ADR.**

| The decision… | goes where |
|---|---|
| **refines, corrects or extends** one that exists | the ADR's text is updated to state the current decision, and a dated line is added to its **Revisions** |
| **changes** a decision other documents cite | a new number; the old ADR's header says *superseded by* and the clause is removed or marked |
| **opens a subject no ADR covers** | a new number |

A decision becomes an ADR when it is cited by more than one spec, when a real
alternative was rejected, or when somebody six months from now will ask "why
like this?". Everything narrower belongs where it is used: a port's guarantee
in the port, an operational recipe in the `dop-infra` spec.

**Section numbers are referenced from specs and code** (`ADR-0010 §4`,
`ADR-0008 §5`). A revision keeps existing numbers; new material goes into the
section it refines or at the end.

## The decisions, by subject

### Foundations

| # | Title |
|---|---|
| [0001](0001-infrastructure-behind-ports.md) | Infrastructure behind ports with pluggable adapters — and, when an adapter cannot meet a guarantee, **the adapter pays** |
| [0012](0012-stack-go-core-python-bff.md) | A core in Go, a BFF in Python, and the boundary between them: **the BFF has no database and no secret** |
| [0013](0013-proto-as-source-of-truth.md) | The `.proto` is the contract's source of truth |

### Accounts, identity and access

| # | Title |
|---|---|
| [0002](0002-account-as-unit-of-ownership.md) | Tenancy: the account owns everything, and an organization proves itself by domain |
| [0019](0019-invite-without-token.md) | The invite has no secret: identity in place of a bearer |
| [0020](0020-second-factor-in-the-core.md) | The second factor is the platform's, with three verifiers |
| [0022](0022-the-core-verifies-its-callers.md) | The core verifies a signature; it does not believe a header |

### Resources, integrations and credentials

| # | Title |
|---|---|
| [0009](0009-resource-as-unit-of-sharing.md) | The resource as the account's unit of ownership and sharing |
| [0003](0003-organization-credential-human-authorship.md) | An organization credential to act, human authorship on the commit — **every rule about commits and push lives here** |

### State and events

| # | Title |
|---|---|
| [0004](0004-demand-as-event-log.md) | The demand is an event log; everything else is a projection |
| [0014](0014-postgres-persistence.md) | PostgreSQL as the single database, and the outbox that moves its events |

### The agents and their cost

| # | Title |
|---|---|
| [0007](0007-multi-agent-per-demand.md) | Multi-agent per demand: addressable threads and published findings |
| [0011](0011-project-orchestrator.md) | The project orchestrator: the techlead agent |
| [0016](0016-agent-provider-as-port.md) | The agent runtime: a port per vendor, running inside the core |
| [0008](0008-llm-cost-governance.md) | The LLM's cost: measuring it, capping it, routing it, and spending less *(the routing table is a draft)* |

### Knowledge and context

| # | Title |
|---|---|
| [0006](0006-context-as-subsystem.md) | Context is a subsystem: a knowledge base and a package per demand |
| [0021](0021-project-knowledge-as-a-git-repository.md) | The project's knowledge is a git repository, hosted by the platform |

### The work, its verification and its delivery

| # | Title |
|---|---|
| [0010](0010-dynamic-workflow.md) | A dynamic, typed and inheritable workflow |
| [0017](0017-sandbox-per-demand.md) | A microVM per demand, with a single shared worktree *(verification clause superseded by 0023)* |
| [0023](0023-verification-runs-from-source.md) | Verification builds from source in a runner, not from an image |
| [0005](0005-no-green-no-pr.md) | No green, no PR: native verification, and a merge queue per repository |

### Communication

| # | Title |
|---|---|
| [0018](0018-communication-trigger-and-channel.md) | Communication: the trigger and the channel are born together |

### Environment and infrastructure

| # | Title |
|---|---|
| [0015](0015-firebase-emulators-and-single-owner.md) | Firebase emulators in the local environment; Terraform as the single owner |

## The renumbering of 2026-09-17

The numbers are **contiguous**: 0001 to 0023, one file each, in the order the decisions were
taken. They were not always — seven documents were folded into the ADR that already owned
their subject on 2026-09-04, and their numbers stayed retired until the owner decided that a
sequence with holes in it reads as a sequence with mistakes in it. On 2026-09-17 every ADR was
renumbered, and every reference in the umbrella repository, `dop-core`, `dop-api`, `dop-app`,
`dop-infra` and `dop-t.com` was rewritten in the same commit series.

Anything **older than that day** — git history, commit messages, closed tickets — cites the old
numbers. Resolve them here:

| Before | Now | Subject |
|---|---|---|
| 0006 | [0004](0004-demand-as-event-log.md) | The demand is an event log |
| 0007 | [0005](0005-no-green-no-pr.md) | No green, no PR |
| 0009 | [0006](0006-context-as-subsystem.md) | Context is a subsystem |
| 0010 | [0007](0007-multi-agent-per-demand.md) | Multi-agent per demand |
| 0011 | [0008](0008-llm-cost-governance.md) | The LLM's cost |
| 0013 | [0009](0009-resource-as-unit-of-sharing.md) | The resource as the unit of sharing |
| 0014 | [0010](0010-dynamic-workflow.md) | A dynamic, typed and inheritable workflow |
| 0015 | [0011](0011-project-orchestrator.md) | The project orchestrator |
| 0016 | [0012](0012-stack-go-core-python-bff.md) | A core in Go, a BFF in Python |
| 0017 | [0013](0013-proto-as-source-of-truth.md) | The `.proto` is the contract |
| 0018 | [0014](0014-postgres-persistence.md) | PostgreSQL and the outbox |
| 0020 | [0015](0015-firebase-emulators-and-single-owner.md) | Firebase emulators; Terraform as the single owner |
| 0022 | [0016](0016-agent-provider-as-port.md) | The agent runtime as a port |
| 0024 | [0017](0017-sandbox-per-demand.md) | A microVM per demand |
| 0025 | [0018](0018-communication-trigger-and-channel.md) | Communication: trigger and channel |
| 0026 | [0019](0019-invite-without-token.md) | The invite has no secret |
| 0027 | [0020](0020-second-factor-in-the-core.md) | The second factor |
| 0028 | [0021](0021-project-knowledge-as-a-git-repository.md) | The project's knowledge is a git repository |
| 0029 | [0022](0022-the-core-verifies-its-callers.md) | The core verifies its callers |
| 0030 | [0023](0023-verification-runs-from-source.md) | Verification runs from source |

0001, 0002 and 0003 kept their numbers.

The seven folded on 2026-09-04 resolve to the ADR that absorbed them — the old number is the
one in git history before that date:

| Was (old number) | Subject | Now lives in |
|---|---|---|
| 0004 | Verifying an organization by domain | [0002](0002-account-as-unit-of-ownership.md) §3 |
| 0005 | A multi-tenant platform with organizations | [0002](0002-account-as-unit-of-ownership.md) §1 |
| 0008 | A merge queue per repository | [0005](0005-no-green-no-pr.md), rules 5–8 |
| 0012 | Token economy as an engineering discipline | [0008](0008-llm-cost-governance.md) §4–9 |
| 0019 | A transactional outbox + NATS JetStream | [0014](0014-postgres-persistence.md) §2–4 |
| 0021 | Read-after-write of a secret is not free on GCP | [0001](0001-infrastructure-behind-ports.md), "When an adapter cannot meet a guarantee" |
| 0023 | The AgentRuntime lives in the core | [0016](0016-agent-provider-as-port.md) §2 |

**The rule from here on:** a folded ADR's number is not left as a hole; the sequence is
renumbered, this table grows, and the references are rewritten in the same change.

## Consistency review — 2026-09-20

All twenty-three ADRs were rewritten into the shape above, without changing
any decision. The review across them resolved these divergences:

| subject | was | now |
|---|---|---|
| where the agent runtime runs | ADR-0012 said the BFF (struck through); ADR-0016 said the core | ADR-0012 states the core and references ADR-0016; the BFF's rule reads "no database and no secret" in one place |
| where verification runs | ADR-0017 "an ephemeral pod per run" (superseded in prose); ADR-0023 a runner from source; a P-27 write-up said "in the sandbox" | ADR-0017 §4 states the runner and the per-demand address; ADR-0023 owns the mechanism; the sandbox is never the verification environment |
| the dead-letter queue | ADR-0014 described a DLQ as existing; the mechanism was in a spec amendment | ADR-0014 §3 states the built design: `dlq.event`, `DeadLetter`, `MaxDeliver 5`, backoff `1s/5s/15s/1min`, 3 retries from the DLQ, classification, `event_errors` |
| the event envelope | ADR-0004 listed six fields; the code carries twelve | ADR-0004 §2 lists the fields of `ports.Event` |
| where knowledge text lives | ADR-0006 "over `ObjectStore`", revised in a trailing note; ADR-0021 git | ADR-0006 §1 states git for text and `ObjectStore` for bytes; ADR-0021 owns the repository |
| transport authentication | ADR-0022 a NetworkPolicy, with a Cloud Run IAM amendment | ADR-0022 §6: Cloud Run IAM on the managed deployment, a NetworkPolicy on clusters, both additional to the signature |
| the session identifier the step-up trusts | ADR-0020 flagged the BFF's metadata as unverified (P-18) | ADR-0020 §5 references ADR-0022: the session id is in the verified metadata |
| the idempotency key's namespace | ADR-0013 described it as a lesson | ADR-0013 §4 states the rule: scoped to the owning account; platform rows under a nil-uuid namespace |
| the notification link | ADR-0019 described `Rule.LinkPath` | ADR-0018 §8 owns link paths as data; ADR-0019 §3 references it |
| the `Mailer` adapters | ADR-0018 listed SendGrid and SMTP, OneSignal as "future" | ADR-0018 §4 lists the three built adapters |
| "two adapters and a contract suite" | restated in most ADRs | stated in ADR-0001 §4; others reference it |
| commit attribution | ADR-0003 and ADR-0021 | ADR-0003 only; ADR-0021 references it |
| absorbed numbers | header sentences about retired numbers in five ADRs | a dated Revisions line; the mapping lives in this index |
