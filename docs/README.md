# The DOP platform — documentation

A platform where agents do software development work inside an organization's own process:
demands, specs, verification and delivery, with a human deciding at the gates.

**Start here if you are looking for…**

| | |
|---|---|
| **what a word means** | [`GLOSSARY.md`](GLOSSARY.md) — read this first if two documents seem to disagree; most collisions are vocabulary (bench × runner, application × dependency) |
| **what is decided, and why** | [`adr/`](adr/README.md) — 23 decisions, grouped by subject. The index also carries the rule for **when a new decision does not become a new ADR** |
| **how a subsystem works** | [`superpowers/specs/`](superpowers/specs/) — the designs. A spec cites the ADRs; it does not restate them |
| **what is built and what is missing** | [`ROADMAP.md`](ROADMAP.md) — subprojects, state, and the numbered pendings (P-*) |
| **what the product does, for whom** | [`prd/`](prd/) — the user stories and the MVP |
| **why something was reviewed** | [`analysis/`](analysis/) — dated readings that produced ADRs. Historical: they describe the day they were written |

## The repositories

| | |
|---|---|
| `dop-core` | Go. The domain, the state, the transactions, the events, the orchestration. It holds the vault and **never returns a secret** |
| `dop-api` | Python. The BFF: the edge that authenticates, aggregates and translates protocol. **No database, no secret** |
| `dop-app` | React + Vite. The cockpit |
| `dop-cli` | The platform's command line |
| `dop-cmd` | The developer's environment tool (a different thing from `dop-cli` — see its `docs/`) |
| `dop-infra` | Terraform, the k3d local cluster, the images |

## The specs

| | |
|---|---|
| [`sp0-identity-and-tenancy`](superpowers/specs/sp0-identity-and-tenancy.md) | Users, accounts, organizations, membership, the second factor |
| [`sp0-resources`](superpowers/specs/sp0-resources.md) · [`sp0-integrations-and-credentials`](superpowers/specs/sp0-integrations-and-credentials.md) | What is owned and shared, and how a credential is held |
| [`backend-architecture`](superpowers/specs/backend-architecture.md) | The core, the BFF, the boundary, the schema |
| [`workflow`](superpowers/specs/workflow.md) · [`conversation-and-attention`](superpowers/specs/conversation-and-attention.md) | The demand's flow, and where a human is asked |
| [`context-and-knowledge`](superpowers/specs/context-and-knowledge.md) | The project's shelf and the package a demand carries |
| [`demand-execution`](superpowers/specs/demand-execution.md) | The **bench**: where the agent works |
| [`verification-runner`](superpowers/specs/verification-runner.md) | The **runner**: where the application is built and run |
| [`verification-and-delivery`](superpowers/specs/verification-and-delivery.md) | From green to `main`: the critic, the evidence, the queue |
| [`navigation-and-cockpit`](superpowers/specs/navigation-and-cockpit.md) | What the screen shows |
| [`dop-infra`](superpowers/specs/dop-infra.md) | The environments |

## Two conventions that are easy to violate

**Everything in the repository is written in English** — code, comments, logs, paths, protos,
documentation, READMEs. What a person reads on screen goes through i18n.

**One subject, one ADR.** A refinement is a dated amendment inside the ADR that owns the
subject, not a new number. The reasoning is in [`adr/README.md`](adr/README.md).
