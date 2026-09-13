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
| **Second factor** | The second step of a sign-in, the platform's and not the identity provider's (ADR-0027). Three kinds: `totp` (an authenticator app), `email` and `sms` |
| **Step-up** | The state of a session that has already answered the second factor, with an expiry. It is what gates a sign-in and the sensitive operations, never a read |
| **Recovery code** | One of ten single-use codes, shown once and kept hashed, which recover an account when the factor is lost. It is what stops support from becoming the bypass |
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
| **dop-core** | The core in Go: domain, state, transactions and events. One binary, **five** modes: `serve` (the gRPC surface, and the host of the projects' git server), `worker` (consumers and projections), `sched` (periodic work), `launcher` (raises sandboxes), `collector` (the only mode that runs INSIDE a sandbox, following the agent's session file) |
| **dop-api (the BFF)** | The edge in Python: REST+SSE for the app, gRPC for the CLI and the sandbox. It has no database and no secret |
| **Outbox** | The table where the event is written in the same transaction as the state; a relay publishes to the broker — atomicity with no 2PC |
| **Projection** | A read derived from the event log (the dossier, the timeline, the attention box, the metrics). It never writes the truth |
| **Card** | A work item coming from the task manager. It has a dynamic type, defined by the provider |
| **Demand** | A card in execution on the platform: a sandbox, threads, a spec, events. The card is the origin; the demand is the work |
| **Aggregate** | The thing a fact belongs to: the noun whose history that event becomes part of. `account`, `demand`, `resource`, `workspace`. Every event carries `aggregate` (the type) and `aggregate_id` (which one); the index `events_aggregate_idx` is what makes "everything that happened to this one" cheap. The test: would you open a screen to see its history? |
| **Aggregate key** (`aggregate_key`) | The aggregate's readable handle at the time of the event (`acme`), so a person or an agent can discuss a fact without a uuid. A snapshot: renaming the aggregate does not rewrite events already recorded. |
| **Dead letter** | The record of an event no consumer could process after every retry. One queue for the whole platform, carrying the event, its context and the attempt history in one payload. |
| **Executor** | **Who executes the container.** There are two, and only two: the **Kubernetes cluster** (k3d locally, k3s/OKD or GKE in production) and the **host's Docker daemon** (a laptop, no cluster). One is chosen at boot by `SANDBOX_BACKEND`. It exists as a word because the domain never says "pod" or "container" — it says *launch a sandbox* — so something has to name whichever technology is answering. Same nature as the vault being GCP Secret Manager or a k8s Secret (ADR-0001's infrastructure ports: one active, chosen by the deployment). **Executor is the WHERE; the sandbox and the runner are the WHAT** — two different things running on the same executor at the same time |
| **Sandbox (the bench)** | Where the AGENT works: one per demand, with the workspace, the shelf and the agent's containers. It holds the dirty working tree, and everything installed along the way. A security boundary — it runs untrusted code. **It does not run the demand's application** |
| **Runner** | Where a VERIFICATION runs: an ephemeral environment, separate from the sandbox, that pulls a COMMIT, builds from source and starts the application (ADR-0030). It starts from nothing, which is what makes its evidence about a clean environment and not about the agent's |
| **The application** | The customer's software, built from source in the runner. **No image of it is ever built, pushed or deployed** — the slow sequence is not the build, it is `build → push → pull` around a registry |
| **Dependency** | A third party the application needs to run: a database, a cache, a broker. Always a PUBLISHED image (`postgres:16`), pulled and never built. The project declares which ones and which versions — a few lines, not a translation of its compose file |
| **Provisioning** | Creating an environment. It is two different acts and they are decided separately: provisioning the **bench** (so the agent can work) and provisioning a **runner** (so a verification can run, or so a developer can look at the application) |
| **Dev session** | A runner a developer asked for, to click through the application. Same build from the same kind of commit; it holds the demand's address and dies on a deadline. It may run the checks first — "test it and leave it up for me" is one request, not two |
| **The demand's address** | `<service>--<demand>.<domain>` — ONE per demand (P-27). Published for a DEV SESSION and nothing else: a verification's checks reach the application at `localhost` inside the run, so nothing queues for the address |
| **Subagent** | A specialist agent launched inside the demand, in the same sandbox, with a card of its own (purpose, tools, model, budget) |
| **Thread** | The conversation timeline with one of the demand's agents. One per agent; queryable by its siblings |
| **Finding** | A structured result published by an agent on concluding an investigation. It becomes an event, a dossier entry and a memory |
| **Context package** | The luggage assembled per TURN into the prompt: the spec + the rules + the index of the repos involved + the relevant memories. Curated and budgeted — not the shelf |
| **Root repository** | A project's own git repository, born with the project in the platform's git server, holding its knowledge as files (`rules/`, `index/`, `memory/`, `demand/<id>/`). Every sandbox of the project clones it at `/project`; the user may attach a remote of theirs as a mirror (ADR-0028) |
| **Shelf** | The clone of the root repository inside the sandbox: complete, read-write, with a generated `README.md` as its manifest. Costs nothing until a file is opened — the opposite of the package |
| **Artefact** | A file at `demand/<id>/<kind>.md` in the root repository — spec, plan, test plan, report — declared by a flow's stage (ADR-0014). Rendered bytes stay in the ObjectStore, referenced from the file |
| **Critic** | An independent instance that reviews diff × spec before the human. A strong model, a clean context |
| **Evidence package** | What accompanies the PR: acceptance, tests, the critic's opinion, links to the trace |
| **Merge queue** | A per-repository queue that reapplies each PR over the current main and re-verifies before merging, one at a time |
| **Attention box** | A single queue, across all the active account's demands, of the items that require a human decision. It is not the chat: it leads to the right chat |

## Words that were being used for two things

These are the collisions that actually cost us time, written down so they stop.

**"Stack" is not one thing, so the word is avoided.** It was used for the
application the developer pokes at while the agent works, AND for the environment
where tests produce evidence. They have different lifetimes, different cleanliness
and different owners. Say **bench** for the first and **runner** for the second;
say **the application** for the software itself and **dependencies** for what it
needs to run.

**"Provisioning" is not one act.** Raising the bench is one decision; raising a
runner is another. A sentence that says "provisioning happens after development"
is true of the runner and false of the bench — the bench is where development
happens.

**"Sandbox" is the bench, always.** It is the agent's environment. The runner is
not a sandbox, even where the executor happens to implement both as pods: what
separates them is that one carries the dirty tree and the other starts from a
commit.

**"Substrate" is gone, and it is not coming back.** Until 2026-09-05 the
technology that runs a container was called the *substrate* — a word coined in
this repository on 2026-08-29 and never a standard term anywhere. It ended up
doing three jobs at once: the technology, the whole execution LAYER ("the
substrate is running ahead of the work model", epic 07), and — by filename —
the bench. It was replaced by **executor**, which is what the industry calls
exactly this (GitLab Runner has `docker` and `kubernetes` executors; Nomad calls
them task drivers). For the layer, say **the execution layer**; for the bench,
say **the bench**; and the spec that carried the old name is now
[`demand-execution.md`](superpowers/specs/demand-execution.md).

The word the CODE uses is still `backend` — `SANDBOX_BACKEND` chooses which
executor answers. Renaming an environment variable breaks every deployment that
sets it, so the identifier stays and the prose says executor.

**"Building" is not one act either.** Building the APPLICATION from source is
what a runner does on every verification. Building an IMAGE is what the platform
deliberately does NOT do for a customer's application (ADR-0030) — the only
images built are ours, and they are built once.

**The context package is not the shelf.** The package is curated, budgeted, and
paid for on every turn because it goes into the prompt. The shelf is the whole
repository on disk, and it costs nothing until a file is opened.

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
