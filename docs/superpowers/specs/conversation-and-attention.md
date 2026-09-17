# Multi-agent conversation and the attention box

> **Status:** Approved for review · **Date:** 2026-08-29 · **Project:** the DOP platform
>
> **Answers:** how the dev talks to a demand's agents (threads) and how the platform directs
> their attention across all the demands (the attention box).
>
> **Does not answer:** the chat's transport protocol (SP-2); the final screens (the cockpit's
> design evolves over the existing dop-app).

The base decisions: [ADR-0007](../../adr/0007-multi-agent-per-demand.md),
[ADR-0004](../../adr/0004-demand-as-event-log.md),
[ADR-0008](../../adr/0008-llm-cost-governance.md).

## 1. Threads per demand

```
SUOPT-1315
├── #main         the main agent ←→ the dev
├── #db-forensics a subagent (the MySQL MCP) ←→ the dev
└── #logs         a subagent ←→ the dev
```

- Each thread has its own timeline; every message is an event (ADR-0004).
- **The thread's cycle:** `open → active → blocked (a pending question) → concluded`.
  Concluding requires publishing the **finding** — the thread does not die in silence.
- **The subagent's card** (visible in the thread): purpose, tools granted (the workspace's
  MCPs — R1.14), model, slice of the budget.
- Who launches: the human through the chat, and the main agent on its own initiative — the
  thread shows up immediately (an assumption recorded in ADR-0007, subject to veto).

## 2. Cross knowledge

- **Querying between threads:** `read_thread(id)`, `ask(id, question)` — the agents' tools,
  with a synchronous answer or one through a finding.
- **The demand's findings board:** a structured result published on concluding an
  investigation; it goes automatically into the siblings' context, into the dossier and into
  the project's memory (ADR-0006).
- Raw timelines are **not** injected into somebody else's context — it does not scale and it
  widens injection.
- **An operator's intervention** in a thread (an instruction coming from the attention box)
  comes in as a `system` message in the middle of the conversation — it preserves the cached
  prefix (ADR-0008).
- **Investigation-thread hygiene:** once the finding is published, the raw tool results (dumps,
  logs) are cleaned from the transcript by context editing; the finding is the durable record.

## 3. The attention box

The single queue, across **all** the active account's demands, answering "where am I needed,
and in what order". It is not the chat: it is what leads to the right chat.

| Item type | Origin | Where the click leads |
|---|---|---|
| An agent's question / a blocked thread | ADR-0007 | the thread |
| A spec waiting for approval | the spec's cycle (SP-4's core) | the spec |
| A PR waiting for review | ADR-0005 | the PR with its evidence |
| A conflict escalated from the merge queue | ADR-0005 | the conflict's context |
| **A cross-cutting situation detected by the techlead** — a dependency, an overlap, an interference — with ready directive options and a recommendation | ADR-0011 | the coordination decision |
| A demand paused on budget | ADR-0008 | a spending decision |
| The account's integration broken | the integrations spec, R-1 | the integration |

- **Priority** by impact (a merge queue's production item > an exploratory question) and age;
  items are groupable per demand.
- The scope: the **active account** (SP-0); the view crosses its workspaces and projects — it
  is the PRD's R2.9 promoted from "proposed" to a central primitive.
- Every item is born of an event (ADR-0004) — the box is a projection, not a system.

## 4. Risks

| # | |
|---|---|
| R-1 | A noisy box becomes noise and is ignored — only what requires a human decision gets in; status and progress stay in the cockpit |
| R-2 | 5 demands × 3 threads = 15 conversations: without the box, the multi-agent model drowns the dev — both go up together or neither does |
| R-3 | Notification outside the platform (e-mail, push) is left for later; the box is the source, channels are future projections |
