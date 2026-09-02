# Glossary — the DOP platform

The project's vocabulary. When a term here collides with an external provider's, the
disambiguation convention is recorded.

| Term | Meaning |
|---|---|
| **Platform** | Level 0. It holds the global resources that belong to nobody: the catalogue of providers, templates, skills |
| **Account** | The unit of ownership and isolation. It has a `kind`: `personal` (an individual) or `organization` (a company). It owns integrations, workspaces and projects |
| **Active account** | The account the user is operating under at the moment, chosen in the selector. Every API call carries one |
| **User** | A person's identity. It exists once on the platform, regardless of how many accounts they reach |
| **Membership** | The link between a user and an account, carrying a role. The role lives in the membership, not in the person |
| **Grant** | A user's authorization over a specific integration, with level `use` or `manage`. Orthogonal to the role |
| **Workspace** | Level 1. It groups projects. It has a name, a key, a description and a tag schema |
| **Project** | Level 2. Where the repositories and the task manager's space live, consumed from the owning account's integrations |
| **Resource** | The account's unit of ownership and sharing: an integration, a skill, a human↔agent workflow or a git flow. A `use`/`manage` grant per user |
| **Integration** | A resource with a credential: the account's link to an external provider — git, task manager or **agent** (Claude, Codex, …) |
| **Git flow** | A resource that declares the git governance: the branch taxonomy per card type, bases, promotion, policies |
| **Workflow** | A resource that composes the demand's cycle into typed stages, with artifacts and gates (ADR-0014). Inheritable along the chain platform ◁ account ◁ workspace ◁ project ◁ demand |
| **Typed stage** | An element of the flow whose type (context, spec, plan, implementation, test, human_validation, finalization, generic) decides the screen's renderer and the agent's behaviour |
| **Gate** | A point in the flow where the demand stops and waits for a human decision; it becomes an item in the attention box |
| **Effective flow** | The flow that holds for a demand after resolving the inheritance chain; the version freezes when the demand starts |
| **Techlead (the project orchestrator)** | The project's agent, activated with parallel demands: it detects cross-cutting situations, plans and prompts decisions in the attention box; it never pauses demands (ADR-0015) |
| **Coordination directive** | The dev's decision about a cross-cutting situation, applied by the demands' agents (e.g. a conditioned cherry-pick, an order in the queue, file partitioning) |
| **dop-core** | The core in Go: domain, state, transactions and events. One binary, four modes (`serve`, `worker`, `sched`, `launcher`) |
| **dop-api (the BFF)** | The edge in Python: REST+SSE for the app, gRPC for the CLI and the sandbox. It has no database and no secret |
| **Outbox** | The table where the event is written in the same transaction as the state; a relay publishes to the broker — atomicity with no 2PC |
| **Projection** | A read derived from the event log (the dossier, the timeline, the attention box, the metrics). It never writes the truth |
| **Card** | A work item coming from the task manager. It has a dynamic type, defined by the provider |
| **Demand** | A card in execution on the platform: a sandbox, threads, a spec, events. The card is the origin; the demand is the work |
| **Sandbox** | A demand's isolated environment: a microVM with the agent(s), the workspace and an internal Docker. A security boundary |
| **Subagent** | A specialist agent launched inside the demand, in the same sandbox, with a card of its own (purpose, tools, model, budget) |
| **Thread** | The conversation timeline with one of the demand's agents. One per agent; queryable by its siblings |
| **Finding** | A structured result published by an agent on concluding an investigation. It becomes an event, a dossier entry and a memory |
| **Context package** | The luggage assembled per demand: the spec + the rules + the index of the repos involved + the relevant memories |
| **Critic** | An independent instance that reviews diff × spec before the human. A strong model, a clean context |
| **Evidence package** | What accompanies the PR: acceptance, tests, the critic's opinion, links to the trace |
| **Merge queue** | A per-repository queue that reapplies each PR over the current main and re-verifies before merging, one at a time |
| **Attention box** | A single queue, across all the active account's demands, of the items that require a human decision. It is not the chat: it leads to the right chat |

## Mandatory disambiguations

**"Workspace" is DOP's concept and only that.** Task managers also use the word — ClickUp
calls its tenant that. That side is called the **provider's space**, or is always qualified:
*a ClickUp workspace*. The bare word never refers to the provider.

**"Project" in DOP is level 2.** When speaking of a project in Jira, Azure DevOps or GCP,
always qualify it: *a Jira project*, *a GCP project*.

## A renaming under way

What the earlier documentation and code called a **workspace** is now called a **project**,
and the name *workspace* was reused for the grouping above it. Old material may use the old
sense — see P-5 in [`ROADMAP.md`](ROADMAP.md).
