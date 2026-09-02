# Navigation and the cockpit

> **Status:** Approved (rev. 2 — panel-over-bar, 2026-08-30) · **Project:** the DOP platform
>
> **Answers:** the platform's navigation pattern and the cockpit's anatomy.
> **The base:** ADR-0014 (the dynamic flow), ADR-0010 (threads), ADR-0006 (events).
> The clickable prototype of 2026-08-29 validates the global chrome and the scopes; this
> revision's internal cockpit anatomy (panel-over-bar) replaces it and will be prototyped in
> the next visual iteration.

## 1. Principles

- **Zero screens before the work.** Signing in lands on the last cockpit; a project is 1
  click away, a demand 1 click, a workspace 2. Configuration is a sliding panel, never a page.
- **The cockpit's law: the panel is "what", the centre is "the content".** Every function —
  current or future — is a panel+centre pair in the same pattern (§3). A new function does not
  touch the chrome.

## 2. The global chrome

A thin header (the logo, the active account selector, a breadcrumb, the global attention box
🔔, ⌘K); a side tree of workspaces→projects with search; sliding configuration panels.
Unchanged since rev. 1. Outside the cockpit there is only Auth and First use.

## 3. The cockpit's anatomy

```
┌───────────────────────────────────────────────────────────────┐
│  [Overview]                            ← above the task header,│
│  task header: a strip of cards (it filters everything below) outside it │
├────┬─────────────────┬────────────────────────────────────────┤
│ 💬 │                 │                                        │
│ 📁 │  PANEL          │   CENTRE                               │
│ 🖥 │  overlays the   │   driven by the panel's options        │
│ ✓  │  bar; the bar   │   (in the Chat: the flow's stages)     │
│ 🏛 │  shrinks to     │                                        │
│ ⏱ │  icons          │                                        │
└────┴─────────────────┴────────────────────────────────────────┘
```

- **The navigation pattern (the VS Code pattern):** clicking a button on the bar opens the
  **panel** over the bar, which shrinks to icons so functions can be switched; the **centre**
  responds to the selection in the panel. The panel is collapsible; widths are persisted per
  function.
- **The task header** (a strip of cards with a double status, filterable): the selection
  defines the scope of the bar, the panel and the centre. Clicking the card's chip opens the
  provider's card detail (the original card + its artifacts).
- **The Overview stays above the task header, outside the bar** — it does not respond to the
  card filter, and its position says so. In v1 it is a button that takes over the centre; its
  final shape will be explored later (P-10). One Overview item is already defined: **the
  project's architecture** — general analyses generated at the dev's request from source code,
  documents, repositories and infrastructure resources, to generate knowledge and identify
  stacks, integrations and strong/weak points, **proposing improvements** in diagrams and
  charts (e.g. "100 integrations, 90 with no resilience" — a diagram of the flow with no
  resilience + a chart of the index). It is distinct from the bar's Architecture: the bar's is
  per task; the Overview's is of the whole project, immune to the filter.
- **The scopes:** project (no card) and demand (a card selected). The deep URL
  `/:account/:workspace/:project?card=` is preserved.

## 4. The bar's functions

| Function | Panel | Centre |
|---|---|---|
| **Chat** | The demand's threads: `#main` + subagents, cards, findings, launching a subagent (ADR-0010) | **The effective flow's stage ruler** (ADR-0014), in tabs — artifacts, gates and a renderer per stage type |
| **Repos** | The full git tree: repos → branches → PRs/MRs → files (modified, ignored, gitStatus) → **the merge queue** (ADR-0008) | The diff, the file, the PR's detail with its evidence package, the queue's state |
| **Infra** | Three groups: **applications** (the demand's pods/containers), **databases**, **remote services** — with their state | Streaming logs, a terminal, the resource's detail. **It reaches the application's environment, never the agent's microVM** |
| **QA** | Quality groups: Acceptance (the spec's criteria) · Tests (aaa/e2e/integration) · Coverage · Allure reports · History/flakiness · **Standards & conformance · Duplication · Complexity & debt · Dependencies & vulnerabilities** (a Sonar-like stack in a container) | The selected group's panel |
| **Architecture** | **The demands' architectural artifacts**, grouped per task and per type — diagrams (architectural, flow/operational), technical documents, opinions/executive reports — plus the project's map (the ADR-0009 index) in the project scope | An interactive canvas for diagrams (e.g. Claude Design), a viewer for documents. **Tied to the tasks and filtered by the task header**: in the demand scope, only that task's artifacts |
| **Timeline** | Event filters/groupings: agents, git, gates, cost | The timeline (a projection of the log — ADR-0006): who did what, with which credential; cost and cache (ADR-0011/0012). It is where auditing and replay become visible |

**The QA × Architecture split: QA measures, Architecture explains.** Every index — of product
or of code — is QA; Architecture is a **product of the work**: its artifacts are born of the
dev's requests inside the demands (asking for an integration diagram of a feature, a forensic
reading of a hotfix that yields an opinion with diagrams and a technical document) — subagents
with a thread in the Chat (ADR-0010), the result recorded as an artifact of the demand and in
the project's memory (ADR-0009).

**Not functions of the bar** (an explicit decision): Spec/Docs (artifacts live in the stages);
Cost (a Timeline group; the account in configuration); Security (a QA group in v1, promoted if
it grows); the attention box (global, in the header).

## 5. The Chat's centre — rendering the flow

The centre reads the demand's **effective flow** (ADR-0014's structure) and draws the stage
ruler without knowing any composition: the stage's **type** picks the renderer — MD documents
(context/spec/plan), execution progress (implementation), aaa/e2e/integration tabs (test), a
**validation checklist with tickable plans and links** (human_validation), **steps with states
and PR generation** (finalization). The renderers derive from the components already defined
in dop-app (ValidationStageView, FinalizationStageView, doc-viewer, test-stage-view) —
rethought, not discarded.
