# Base PRD — DOP 1.0 (the MVP)

> **A living document.** It captures every requirement of DOP 1.0 from the Dev's vision. It
> will serve as the source for slicing into *feature PRDs* and for the division of
> responsibilities Dev × Claude.
>
> - **Status:** A draft for review
> - **Date:** 2026-05-30
> - **Current base:** dop 0.5.0 (a multi-workspace, multi-platform CLI, with a data-driven
>   runtime)
> - **A non-goal of this document:** deciding architecture/stack/implementation (that is
>   Claude's responsibility, see [§10](#10-open-technical-decisions-claudes-to-take)). Here the
>   focus is **what** and **for whom**, not **how**.

## Contents

1. [The vision and the value proposition](#1-the-vision-and-the-value-proposition)
2. [1.0's goals and non-goals](#2-10s-goals-and-non-goals)
3. [Actors, personas and the division of responsibilities](#3-actors-personas-and-the-division-of-responsibilities)
4. [High-level architecture (descriptive)](#4-high-level-architecture-descriptive)
5. [Concepts and states](#5-concepts-and-states)
6. [Capabilities / epics and requirements](#6-capabilities--epics-and-requirements)
7. [Inference (reducing the Dev's work and error)](#7-inference-reducing-the-devs-work-and-error)
8. [Non-functional requirements](#8-non-functional-requirements)
9. [The feature map and the division of responsibilities](#9-the-feature-map-and-the-division-of-responsibilities)
10. [Open technical decisions (Claude's to take)](#10-open-technical-decisions-claudes-to-take)
11. [Open product questions (to validate with the Dev)](#11-open-product-questions-to-validate-with-the-dev)
12. [Out of 1.0's scope](#12-out-of-10s-scope)
13. [Glossary](#13-glossary)

---

## 1. The vision and the value proposition

DOP evolves from a **CLI** into an **AI-first tool that assists software development**, made of
three components — **the CLI, the API and the Frontend** — in which the **Dev** and **Claude**
collaborate to run demands from start to finish (setting up the environment → development → the
PR → delivery).

The CLI keeps doing everything it does today (multi-platform git/PR, a docker-compose runtime,
e2e). What is new is **exposing those capabilities through an API** and offering a **Frontend**
where the Dev works by talking to Claude, with rich visibility of each demand's state.

**The anchor sentence:** *"A cockpit where the Dev and Claude develop together — from the
workspace's configuration to the delivered PR — with Claude operating DOP underneath and the Dev
following and guiding from above."*

## 2. 1.0's goals and non-goals

### Goals
- **O1.** Three integrated components: the **CLI** (the engine), the **API** (HTTP
  orchestration), the **Frontend** (the Dev's UI).
- **O2.** **Every action the CLI does today** is triggerable through the API.
- **O3.** **Workspaces** configurable through a **wizard** (multi-step, saveable step by step),
  with connection testing, inference and a **configuration chat** with Claude.
- **O4.** A **development flow** guided by demand: list the dev's tasks, work in a chat with
  Claude, follow the status through to delivery.
- **O5.** A **pluggable task manager** (Jira in 1.0), with the same interface philosophy as the
  runtime/git providers.
- **O6.** **Assisted generation** (by Claude) of the workspace's artifacts (Dockerfiles,
  docker-compose, rules/context).
- **O7.** **Single-user, multi-project in parallel:** one Dev working on **several
  workspaces/demands at the same time**, with a low attention overhead.

### The product philosophy: the Dev is Claude's manager

In 1.0 the Dev acts **more as Claude's manager than as an executor**. Claude is **as autonomous
as possible**: it plans, implements, creates tests, generates **memories** (context, ADRs,
prompts) and does **forensic readings** (e.g. why a PR conflicted, what changed between
branches, why a pipeline failed). The Dev **supplies requirements and context, decides, approves
and steps in when Claude asks** — without micro-managing.

Design consequences:
- The UX is one of **supervision**, not of manual operation: **minimalist**, it shows the
  essentials ("where I am needed", the demands' state) and avoids a proliferation of screens and
  reports.
- With **several projects in parallel**, the Dev's scarce resource is **attention** — the tool
  has to direct attention, not require a manual sweep.

### 1.0's non-goals
- Not replacing remote CI/CD pipelines.
- Not doing automatic PR merge/approval (the human decision stays).
- Not supporting webhooks (merge detection is by **polling** in 1.0).
- Multi-task-manager / multi-git-provider **at the same time** beyond Jira + Azure DevOps (the
  *pluggability* is a requirement; the *extra implementations* are not).

## 3. Actors, personas and the division of responsibilities

### The actors
- **The Dev (a human):** configures workspaces, chooses demands, talks to Claude,
  approves/decides, follows the state. May occasionally use the **CLI** directly.
- **Claude (the agent):** operates DOP (git/PR/runtime/e2e), talks to the Dev, asks questions to
  understand the project, generates artifacts and runs the demand.

### The interaction chain
```
Dev ──▶ Frontend ───────────────▶ DOP API ──▶ the workspace + the tools
                                   ▲   │          (git / azure / jira / docker, the state)
                                   │   └──▶ Claude (the agent) ◀──▶ Dev  (chat)
                                   │                 │
                                   └──── CLI ◀───────┘
                          (Claude runs `dop ...`; the CLI only forwards to the API)
```
- The **API is the core/engine**: it holds the business logic (which today lives in the CLI), it
  **reaches the workspace and the tools** (git/azure/jira/docker) and it **holds the state**. It
  is the **only source of truth**.
- There are **two entry doors to the API**: the **Frontend** (used by the Dev) and the **CLI**
  (used by Claude).
- The **CLI became a thin client of the API**: Claude keeps running `dop ...` as today, but the
  CLI **does not reach the workspace directly** — it translates commands into calls to the API.
  It does everything it does today, but **through the API**.
- **Claude** is hosted/driven by the API, **talks to the Dev** (chat) and **operates DOP** by
  invoking the CLI (→ the API).

### The division of responsibilities (for this 1.0)
| Domain | Responsible | Note |
|---|---|---|
| Product requirements, user expectation | **The Dev** | The source of truth of the "what". |
| UX/UI, screen flows, the Dev's interaction | **The Dev** | The wizard, the dashboards, the chat UI. |
| Requirements of the CLI used by the Dev | **The Dev** | The ergonomics of the occasional CLI. |
| Architecture, stack, integrations, implementation | **Claude** | Freedom to choose/test/implement. |
| Integration with Claude (the mechanism), API↔CLI, persistence, technical security | **Claude** | Decisions in [§10](#10-open-technical-decisions-claudes-to-take). |

## 4. High-level architecture (descriptive)

> A **conceptual** description of the components and the data flow. The technical choices
> (stack, in-process × subprocess, persistence, the mechanism of the chat with Claude) are open
> in [§10](#10-open-technical-decisions-claudes-to-take).

- **Component 1 — the API (the core/engine):** it holds the business logic (today in the CLI),
  it **reaches the workspace and the tools** (git/azure/jira/docker), it **keeps the state** of
  workspaces/demands, it hosts/drives **Claude** and it does the **PR polling**. **The only
  source of truth.**
- **Component 2 — the CLI (a thin client of the API):** the entry door used by **Claude** (it
  keeps running `dop ...` as today). It **does not reach the workspace directly** — it forwards
  everything to the API. Kept ergonomic for the Dev's occasional use.
- **Component 3 — the Frontend:** the SPA where the Dev navigates (the home screen, the
  workspace wizard, the development menu, the task list, the demand's panel, the chat). The
  entry door used by the **Dev**.
- **Claude:** invoked by the API as a collaborator/operator; it **talks to the Dev** and
  **operates DOP through the CLI → the API**, both in configuration and in development.

> **A structural consequence (Claude's/the implementation's to handle):** the logic that today
> lives in the CLI's package (`git/`, `platform/`, `runtime/`, `core/state`) **migrates to a
> core consumed by the API**; the CLI is rewritten as a thin HTTP client. It is the project's
> biggest structural change in 1.0.

**Inherited principles (kept as a requirement):**
- Auditable state (today `.state.json`); idempotent operations; `--dry-run`; **secret redaction
  in every output**; multi-workspace; pluggable providers (git/runtime/**task manager**).

## 5. Concepts and states

### 5.1 The workspace — states
`draft` → `active` → `inactive` → `deleted`
- **draft:** created through the wizard, possibly incomplete (saveable step by step).
- **active:** configured and usable for development.
- **inactive:** temporarily disabled (it does not show up for work, but it is preserved).
- **deleted:** logically removed.

### 5.2 The demand — DOP's status (independent of the status in the task manager)
| DOP status | Meaning |
|---|---|
| `new` | The demand has not started in DOP yet. |
| `doing` | Claude and the Dev are working on it. |
| `done` | The PR is made; Claude and the Dev considered it finished. |
| `delivered` | The PR was merged **and** the pipeline ran in the dev environment. |

- The card shows **two statuses**: the **task manager**'s (Jira) and **DOP**'s.
- The `done → delivered` transition is detected by **periodic polling** (a configurable
  interval), through the API/az-cli/MCP (whichever is simplest) — **with no webhook** in 1.0.

### 5.3 The demand's dossier

Each demand accumulates a consultable **dossier** (a **lean** presentation, not a report):
- **Git:** the repos affected, the branches created, the commits.
- **PRs:** the PRs sent and **merged**, **who approved**, the **conflicts** that occurred.
- **Files handled:** plans, contexts, **ADRs**, source code created/changed.
- **Tests:** the unit tests created and the **e2e** tests created.
- **Quality:** **Allure** reports embedded in DOP's own screen, per demand.
- **Time:** start, end and time spent (per demand and, where it makes sense, per stage).
- **Memories and forensic readings** generated by Claude (persisted as artifacts).
- The applications' **logs** (on the execution screen).

### 5.4 The demand's stage model (BAM at runtime)

A demand is executed in **predefined stages (static in the MVP)** — for example: *plan →
implement → create test specs → e2e → AAA tests → create the PR*. In the MVP the **set of stages
is fixed**; what the **Dev + Claude define are the rules and the flows *inside* each stage**
(each phase's "how"), and **not** the list of stages itself.

> **A future evolution (outside the MVP):** a **dynamic** process — stages defined by Claude +
> the Dev **per demand** through the chat, generating a versionable data structure. In the MVP
> that is simplified to the static set above. (See [§12](#12-out-of-10s-scope).)

The (static) stage structure feeds the **real-time follow-up screen** — a **BAM** (*Business
Activity Monitoring*) — where the Dev:
- sees **each stage's progress** (pending / running / done / blocked);
- **interacts with Claude at runtime** (answers questions, steps in, adjusts the course);
- sees the **applications' logs** during the run.

The **detail/execution screen** combines a **chat + a stage wizard + an e2e test strip** (the
detailed composition in [E10](#e10--stage-by-stage-execution-bam)). The **live view of the
Playwright tests in the browser** is a **separate planning chapter**.

### 5.5 The workspace's folder structure
```
<root>/
├── docs/
│   ├── RFC/
│   ├── ADR/
│   └── prompts/
├── repos/
│   ├── <repo1>/
│   ├── <repo2>/
│   └── ...
└── runtime/
    ├── docker/            # dev Dockerfiles — generated by Claude
    └── docker-compose/    # docker-compose.yaml — generated by Claude at configuration time
```

## 6. Capabilities / epics and requirements

> Each epic becomes (in the next phase) a *feature PRD* of its own. Requirement IDs in the
> `R<epic>.<n>` format.

### E1 — Workspaces (configuration through a wizard)

**The main user story**
> As a Dev, I want a home screen with the option to **create/configure several workspaces**,
> configuring remote repositories, the git provider, the branch flow, the task manager and the
> runtime — testing connections at creation — to prepare the AI-first working environment with
> minimum effort and error.

**Requirements**
- **R1.1** The home screen lists the existing workspaces and allows **creating** a new one.
- **R1.2** A **multi-step** wizard, **saveable step by step**; the Dev may **edit any workspace
  at any step** (complete or incomplete).
- **R1.3** Configure **remote** git **repositories** with the **http/https/ssh** protocol; for
  each type, provide the appropriate **credentials** (login/token; an SSH key).
- **R1.4** Choose the **git provider** (in 1.0: **Azure DevOps**), treated as a **pluggable
  strategy** (in the future: GitLab, GitHub, others).
- **R1.5** Configure the **branch flow**: the base branch and the PR target branches (and the
  workspace's flow rules).
- **R1.6** Configure the **task manager** (in 1.0: **Jira**) as a pluggable provider.
- **R1.7** Configure the **runtime** (apps, deps, infrastructure, the orchestrator) — reusing
  the current data-driven model.
- **R1.8** The application **infers** what it can (see
  [§7](#7-inference-reducing-the-devs-work-and-error)) to reduce the Dev's work and error.
- **R1.9** **Test the connections at creation time** (git, task manager, runtime).
- **R1.10** A workspace listing with **editing**: add/remove repositories, **re-test**
  connections, **update credentials** (tokens, SSH keys).
- **R1.11** **The final step = a chat with Claude** to co-build the workspace: establishing the
  **workspace's rules** (e.g. "do not merge `develop` into the feature branch"), the **workflow
  rules**, and the **project's context** (so Claude understands the project). Claude may **ask
  specific questions**.
- **R1.12** Workspace states as per [§5.1](#51-the-workspace--states).
- **R1.13** Everything that makes up the current `config.toml` has to be configurable through
  the UI (whatever is not inferred).
- **R1.14** *(secondary)* Configure **Claude's extensions** per workspace: **MCPs** (e.g.
  postgres, mysql, and others), **plugins**, **skills** and **custom commands** for Claude. The
  custom commands are **triggerable through auto-complete during the chat** (E6). Isolated per
  workspace.

### E2 — Development (working a demand)

**The main user story**
> As a Dev, I want a menu to **start developing**: I select the workspace, I see my task
> manager's tasks with their status (on the card and in DOP), I select a card and land in a
> **chat with Claude** where we work until the demand is `done`; and I want **rich visibility**
> of what happened on the demand.

**Requirements**
- **R2.1** A menu to start development; **workspace selection**.
- **R2.2** After selecting, **list the provider's tasks** (Jira) **assigned to the Dev**,
  showing the **task manager's status** and **DOP's status** (`new/doing/done/delivered`).
- **R2.3** Selecting a card → the **prompt/chat screen with Claude**.
- **R2.4** The Dev and Claude interact until the demand concludes (→ `done`).
- **R2.5** **Periodic polling** (a configurable interval) to detect a **merged PR** and a
  pipeline run → `done → delivered`. No webhook.
- **R2.6** A **rich demand panel** with the **dossier** ([E9](#e9--the-demands-dossier)): the
  repos affected, branches, commits, pipelines, PRs (sent/merged), who approved, conflicts — in
  a **lean** presentation (not a report).
- **R2.7** Keep a **local base** of the demands — those the Dev **has already worked** and those
  **assigned to them** — with periodic **polling** for **new assignments** (no webhook).
- **R2.8** **A minimalist UX:** on entering the workspace, the Dev sees the essentials (demands
  + state) with no proliferation of screens and reports.
- **R2.9** *(proposed)* **A cross-workspace "where I am needed" view:** a single place that,
  **across all the projects**, highlights the demands that need the **Dev's attention** (Claude
  blocked/asking, a PR waiting for review, a conflict to decide). It is justified by the
  multi-project scenario + the "the Dev as a manager" philosophy.

### E3 — The Task Manager Provider (Jira; pluggable)

- **R3.1** A **task manager provider** interface with a pluggability requirement **equal to the
  runtime's** (a strategy selectable by configuration).
- **R3.2** A **Jira** implementation in 1.0: list the Dev's tasks, read the status, link them to
  DOP's flow. (In the future: ClickUp and others — *out of 1.0's implementation scope*.)
- **R3.3** The provider is **inferred from the workspace's configuration**.

### E4 — The Git Provider (Azure DevOps; a pluggable strategy)

- **R4.1** The git provider as a **strategy** (Azure DevOps in 1.0; pluggable for GitLab,
  GitHub, others). *The base already exists in the CLI (`PlatformProvider`).*
- **R4.2** PR operations (create/list/status/conflict/approver) exposed through the API.

### E5 — The Runtime (data-driven; assisted generation)

- **R5.1** Reuse the current data-driven runtime (a pluggable orchestrator; docker_compose).
- **R5.2** **Claude generates** the dev **Dockerfiles** and the **docker-compose.yaml** during
  the workspace's configuration.

### E6 — Integration with Claude (the chat/agent)

- **R6.1** A chat with Claude available in two contexts: the **workspace's configuration**
  (E1.11) and **development per demand** (E2.3).
- **R6.2** Claude **operates DOP** (it runs actions through the API/CLI) during the
  conversation.
- **R6.3** Claude has the **context** of the workspace (rules, flow, project) and of the current
  demand.
- **R6.4** A conversation history per demand/workspace (persistence — see
  [§10](#10-open-technical-decisions-claudes-to-take)).
- **R6.5** The chat supports the workspace's **custom commands**, triggerable through
  **auto-complete**, and Claude has access to the **MCPs / plugins / skills** configured in the
  workspace (R1.14).
- *The technical mechanism of the integration (the Agent SDK × the API × the claude CLI): open,
  §10.*

### E7 — The workspace's folder structure

- **R7.1** Create/manage the structure of [§5.5](#55-the-workspaces-folder-structure).
- **R7.2** `docs/{RFC,ADR,prompts}` as the workspace's knowledge repository.

### E8 — The CLI (a thin client of the API)

- **R8.1** The CLI is **Claude's entry door** into DOP: it keeps offering the same `dop ...`
  commands as today (it preserves the way Claude operates).
- **R8.2** The CLI **does not reach the workspace directly**; each command translates into
  call(s) to the API. The API is the one that executes and holds the state.
- **R8.3** Every DOP operation is therefore exposed by the **API** and reflected in the CLI (the
  CLI never has a capability the API does not have).
- **R8.4** The CLI stays **ergonomic for the Dev's occasional use** (a product responsibility of
  the **Dev**).

### E9 — The demand's dossier

**The main user story**
> As a Dev (a manager), I want to enter a demand and see **leanly** everything Claude did —
> without too many screens and reports — so I can supervise without operating.

**Requirements** (see the concept in [§5.3](#53-the-demands-dossier))
- **R9.1** Git: the repos affected, the branches created, the commits.
- **R9.2** The PRs **sent** and **merged**, **who approved** and the **conflicts** that
  occurred.
- **R9.3** The **files handled**: plans, contexts, **ADRs**, source code created/changed.
- **R9.4** The **tests** created and the **e2e** tests created.
- **R9.5** **Time**: start, end and time spent (per demand and, where it makes sense, per
  stage).
- **R9.6** **Allure embedded** in DOP's screen, per demand.
- **R9.7** The **demand's logs in real time** — shown on the screen (reachable by the **Dev's
  click**, updating live) **and** reachable by **Claude through `dop`** (→ the API) for
  **auditing and troubleshooting**. They cover three sources:
  - **(a) The applications** involved in the demand — the equivalent of today's `dop log <app>`,
    but rendered on the screen with real-time updates.
  - **(b) The tests** — running the **AAA** and **e2e** tests.
  - **(c) The infrastructure/third-party containers** — e.g. **mysql/mongo**, **allure** and
    other supporting services of the runtime.
- **R9.8** Claude's **memories and forensic readings** persisted as consultable artifacts.
- **R9.9** A **minimalist** presentation: a focus on what matters, with no proliferation of
  screens.

### E10 — Stage-by-stage execution (BAM)

**The main user story**
> As a Dev, I want to follow the demand in **stages, in real time** (Claude planning,
> implementing, creating specs, e2e, AAA, the PR), and to **interact with Claude at runtime**,
> so I can follow and guide without having to ask "how is it going?".

**Requirements** (see the concept in
[§5.4](#54-the-demands-stage-model-bam-at-runtime))
- **R10.1** **The MVP:** the set of stages is **predefined (static)**. The Dev + Claude define
  the **rules and flows *inside* each stage**, not the list of stages. *(In the future: dynamic
  stages per demand — see [§12](#12-out-of-10s-scope).)*
- **R10.2** The (static) stage structure feeds the **runtime stage screen**.
- **R10.3** **Real-time** follow-up of each stage's state (pending / running / done / blocked).
- **R10.4** **Interaction at runtime** with Claude from the execution screen (answering
  questions, stepping in, adjusting the course).
- **R10.5** The execution screen shows the demand's **real-time logs** — applications, tests
  (AAA/e2e) and infrastructure/third-party containers (mysql/mongo/allure/…) — as per
  [R9.7](#e9--the-demands-dossier).

**The composition of the demand's detail/execution screen**
- **R10.6** The screen is composed of three areas: **(1) a chat** with Claude (E6); **(2) a
  stage wizard** showing the **current stage**, the ones **already run** and the **next ones**;
  and **(3) an e2e test strip** (during the e2e stage).
- **R10.7** **The e2e strip (the conveyor):** it shows the tests running with **progress bars**
  and a **status per test** — `running` / `success` / `fail` / `skipped` (and intermediate
  states as needed).
- **R10.8** **"Show it visually"** (a Dev's toggle, with an intuitive label): when on, it
  streams the **Playwright run in the browser itself**, on the **same execution screen**, during
  the e2e phase — the Dev **watches the tests running** as if on a monitor.
- **R10.9** **A separate chapter (dedicated planning):** the **advanced visual experience** of
  the tests (an immersive "meeting-like"/monitor mode) will be **planned separately**. 1.0
  establishes the base — the conveyor + statuses + bars + the "Show it visually" toggle; the
  live *streaming mechanism* is an open technical decision (see
  [D11](#10-open-technical-decisions-claudes-to-take)).

## 7. Inference (reducing the Dev's work and error)

The application has to **infer automatically** as much as possible during configuration, leaving
the Dev only what cannot be deduced. Candidates for inference (to be refined):
- The git provider and the organization/project from the **remote's URL**.
- The apps' names/services and ports from the repositories and/or docker-compose.
- The base branch and the PR targets from the remote repository.
- The task manager / project key from the remote's conventions or from the Dev.
- The folder structure and the app↔repo mapping from the layout in `repos/`.
- FE→BE dependencies and e2e suites from the repositories' structure.

> **The principle:** *infer and ask for confirmation* > *ask from scratch*.

## 8. Non-functional requirements

- **NFR1 — Secret security:** never leak tokens/credentials (reuse the current
  redaction/guard); credentials stored securely (the mechanism in §10).
- **NFR2 — Idempotency & dry-run:** preserve the CLI's idempotent behaviour and `--dry-run` in
  the operations exposed.
- **NFR3 — Auditability:** the state and the history of actions/conversations traceable.
- **NFR4 — Multi-workspace:** isolation between workspaces.
- **NFR5 — Pluggability:** git, the runtime and the **task manager** follow the same
  provider/strategy pattern, selectable by configuration.
- **NFR6 — Polling responsiveness:** merge/pipeline detection at a configurable interval,
  without overloading external APIs.
- **NFR7 — Observability:** logs (with redaction) per workspace/demand.
- **NFR8 — Portability:** no coupling to a specific workspace (the lesson of the runtime
  refactor).

## 9. The feature map and the division of responsibilities

> A preliminary view for the slicing. Each feature becomes a PRD of its own.
> **Owner** indicates who leads the **requirements/decisions** (not exclusivity of execution).

| Feature | Epic(s) | Owner (requirements) | Notes |
|---|---|---|---|
| F0 — The foundation (3 components, the Claude integration, persistence, auth) | E6, E8 | **Claude** | Decisions in §10; it unblocks the rest. |
| F1 — The core + the API; the CLI becomes a thin client | E8, E4, E5 | **Claude** | Migrate the CLI's logic to the API's core; CLI → API. |
| F2 — The Task Manager Provider (Jira) | E3 | **Claude** | It mirrors the current providers. |
| F3 — The Workspace wizard (UI) | E1 | **The Dev** (UX) + Claude (infrastructure) | Multi-step, partial save, connection tests. |
| F4 — Configuration inference | E1, E7 | **Claude** | Reducing the Dev's work/error. |
| F5 — The chat with Claude (configuration + development) | E6, E1.11, E2.3 | **The Dev** (UX) + Claude (the engine) | The collaboration's core. |
| F6 — The development workflow (the list + the demand's panel) | E2 | **The Dev** (UX) + Claude (the data) | A rich UI + polling. |
| F7 — Workspace scaffolding (Dockerfiles/compose) | E5, E7 | **Claude** | Assisted generation. |
| F8 — The CLI (a thin client of the API) | E8 | **The Dev** (ergonomics) + Claude (implementation) | `dop ...` commands → the API. |
| F9 — The demand's dossier | E9 | **The Dev** (UX) + Claude (the data) | A lean view; Allure embedded; time. |
| F10 — Stage-by-stage execution (BAM) | E10 | **The Dev** (UX) + Claude (the engine) | Dynamic stages + interaction at runtime. |

## 10. Open technical decisions (Claude's to take)

> These will be resolved by me (Claude) with freedom to choose/test, and documented as ADRs once
> decided.

- **D1 — The mechanism of the integration with Claude:** the Claude Agent SDK (headless Claude
  Code) × the direct Anthropic API × the `claude` CLI. It affects the chat, operating DOP and the
  context.
- **D2 — Migrating the core and the CLI-as-a-client:** how to extract the current logic from the
  CLI's package into a **core consumed by the API**, and how to rewrite the CLI as a **thin HTTP
  client** preserving the `dop ...` commands. (The direction — CLI → API — is a fixed
  requirement; the "how" is a technical decision.) It includes how the core reuses today's
  `git/platform/runtime/core`.
- **D3 — The stack:** the API's language/framework (probably Python, to reuse the CLI) and the
  Frontend's (an SPA); packaging and local execution.
- **D4 — Persistence:** keeping `.state.json` on disk × a database (workspaces, demands, the
  chat history, the DOP status). Migration/coexistence with the current config.
- **D5 — The usage model and auth:** a **Dev's local tool** × a **hosted multi-user** one (it
  changes auth, isolation, secrets).
- **D6 — Secret storage:** tokens/SSH keys (a keychain/secret store × an encrypted file ×
  environment variables, as today).
- **D7 — Merge/pipeline detection:** the Azure REST API × the `az` CLI × Claude+the Azure MCP.
- **D8 — Real time in the Frontend:** streaming the chat and updating statuses (SSE/WebSocket ×
  polling in the front).
- **D9 — Generating Dockerfiles/compose with Claude:** the flow, validation and versioning.
- **D10 — The data model of the stages + the dossier:** how to represent/persist the stage
  structure (BAM) and the demand's dossier, and how to update the screen in real time (it
  relates to D4 persistence and D8 real time).
- **D11 — Visual streaming of the e2e tests (R10.8/R10.9):** the mechanism to stream the
  Playwright run live to DOP's browser — e.g. a *headed* container + VNC/noVNC, a screenshot
  stream, a Playwright trace/live, or another. It is the heart of the **separate chapter** on
  test visualization; it requires planning of its own.
- **D12 — Claude's extensions per workspace (R1.14/R6.5):** how to provision and isolate
  **MCPs, plugins, skills and custom commands** per workspace, and how to expose them in the
  chat (auto-complete). It relates to D1 (the mechanism of the integration with Claude).

## 11. Open product questions (to validate with the Dev)

- ~~**P1 — The usage model:**~~ **RESOLVED:** **single-user, multi-project in parallel**
  ([O7](#2-10s-goals-and-non-goals)). No multi-user/RBAC in 1.0.
- **P2 — "Done" by whom:** is `done` an explicit joint Dev+Claude decision (a button) or is it
  inferred (the PR created)? Confirm the exact trigger.
- **P3 — The scope of "my tasks":** the Jira task filter (assignee = the Dev? the current
  sprint? the project?).
- **P4 — Editing an active workspace:** changing the configuration of an `active` workspace with
  demands under way — which fields may change and what gets reprocessed?
- **P5 — Where the chat "lives":** a chat per demand, per workspace, or both? Does the history
  vanish when the demand becomes `delivered`?
- **P6 — Multi-repo per demand in the UI:** how the UI presents a demand that touches N
  repositories (branches/PRs/pipelines per repo).
- **P7 — The workspace's rules:** the format (free text for Claude × structured rules that DOP
  also validates).
- ~~**P8 — Stages (BAM): a default × free?**~~ **RESOLVED:** in the MVP the stages are
  **static/predefined**; the Dev + Claude define rules/flows *inside* the stages. *(Still open:
  who marks the stage as done — Claude / the Dev / an inference like "the PR was created". To be
  defined in E10's detailing.)*
- **P9 — Cross-workspace attention (R2.9):** does it come into 1.0 or is it left for later? If
  it comes in, which signals count as "I need the Dev" (a question from Claude, a PR waiting for
  review, a conflict, a blocked stage)?
- **P10 — Capturing the dossier:** what DOP collects automatically
  (git/PR/pipeline/files through a diff) × what Claude has to record explicitly (memories,
  forensic readings, mapping tests/e2e to the demand)?

## 12. Out of 1.0's scope

- Webhooks (detection is by polling).
- Extra task manager implementations (ClickUp etc.) and git providers (GitLab/GitHub) — only the
  **pluggability** is a requirement.
- Automatic PR merge/approval.
- Remote CI/CD managed by DOP.
- Multi-user with advanced RBAC (it depends on P1/D5).
- A **dynamic stage process** (stages generated per demand through the chat, generating a
  versionable data structure) — in the MVP the set of stages is **static/predefined**
  ([§5.4](#54-the-demands-stage-model-bam-at-runtime),
  [E10](#e10--stage-by-stage-execution-bam)).

## 13. Glossary

- **Workspace:** the unit of configuration of a project (repos, providers, runtime, rules) where
  the work happens.
- **Demand / card / task:** a work item originating in the task manager (Jira), run in DOP.
- **Provider:** a pluggable implementation of an integration (git, runtime, task manager).
- **Runtime:** the local execution environment (docker-compose today) of the applications.
- **DOP status:** the `new/doing/done/delivered` cycle (distinct from the task manager's
  status).
- **Inference:** the automatic deduction of configuration to reduce the Dev's work/error.
