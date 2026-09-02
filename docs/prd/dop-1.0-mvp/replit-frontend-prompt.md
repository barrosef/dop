# A prompt for Replit — the DOP 1.0 frontend (mock-first)

> **How to use it:** paste the content of the "PROMPT" section below into the Replit Agent.
> Everything outside it is a note for the team (the Dev/Claude). The frontend is **100% mocked**
> in this phase; Claude will integrate it with the API later. The data layer was designed to be
> swapped for a real HTTP client without rewriting the screens.

---

## PROMPT

You are going to build the **complete frontend** of **DOP** — an *AI-first* tool that assists
software development, where a **Dev** and a **Claude** agent collaborate to run demands (Jira
cards) from start to finish. In this phase, **use mocked data only** (no real backend). The goal
is a navigable, polished and realistic SPA.

### 1. The stack (mandatory)

- **React + Vite + TypeScript**
- **Tailwind CSS** + **shadcn/ui** (Radix) for the components
- **React Router** for navigation
- **TanStack Query** for data fetching (pointing at the mock layer)
- **Zustand** for light UI state (e.g. the wizard, the chat session)
- **lucide-react** for icons
- The folder structure:
  ```
  src/
    app/            # routes/pages
    components/     # reusable UI
    features/       # workspaces, demands, chat, dossier, logs
    lib/
      api/
        types.ts        # ALL the domain's types (the contract)
        client.ts       # the DopApi interface (signatures)
        mockClient.ts   # the mock implementation (fixtures + simulated latency)
        index.ts        # it exports the active instance (mock for now)
      mocks/        # fixtures (workspaces, demands, logs, etc.)
    store/          # zustand
  ```
- **The golden rule:** the screens **only know the `DopApi` interface** (`client.ts`), never the
  mocks directly. Swapping `mockClient` for an `httpClient` in the future must not require a
  change to the screens.

### 2. The product philosophy (a UX guide)

- The **Dev is Claude's manager**, not an operator. Claude is autonomous (it plans, implements,
  tests, generates context/memories, does forensic readings). The Dev supplies
  context/requirements, decides, approves and steps in when called.
- **Multi-project, single-user:** the Dev works on several workspaces/demands in parallel. The
  scarce resource is **attention** — the UI has to **direct attention**, not require a sweep.
- **Minimalism:** show the essentials; **avoid excess screens and reports**. A calm density, a
  clear hierarchy, legible statuses (badges, progress bars).
- Support a **light/dark theme**.

### 3. The map of screens and routes

| Route | Screen |
|---|---|
| `/` | **Home**: a list of workspaces + a "New workspace" action. An optional "Where I am needed" strip (demands asking for the Dev's attention in any workspace). |
| `/workspaces/new` | The workspace **creation wizard** (multi-step, saveable per step). |
| `/workspaces/:id/edit` | **Editing** the workspace (the same wizard, any step; re-test connections, update credentials, add/remove repos). |
| `/workspaces/:id` | **The workspace's view**: a menu to "Develop" + a summary. |
| `/workspaces/:id/demands` | **The Dev's demand list** (Jira cards) with a double status. |
| `/workspaces/:id/demands/:demandId` | **The demand's execution/detail screen** (chat + stage wizard + dossier + logs). |

### 4. The workspace — the wizard

The workspace's states: `draft` | `active` | `inactive` | `deleted` (a visible badge). The
wizard saves **step by step** and allows editing any step (complete or not). Each connection step
has a **"Test the connection"** button (mocked: it returns success/error with latency). The
steps:

1. **Basics** — the name, the root folder, the description.
2. **Git repositories** — a list of remote repos; per repo: the URL and the **protocol
   (http / https / ssh)** with the **credential fields according to the protocol** (login+token
   for http/https; an SSH key for ssh). **The git provider = Azure DevOps** (present it as a
   selection with a note "other providers coming soon"). A test-connection button per repo.
3. **The branch flow** — per repo: the **base branch** and the **PR target branches**; a field
   for the **flow rules** (text).
4. **The task manager** — **Jira** (a selection; a note "others coming soon"): the URL, the
   project, the credentials; test the connection.
5. **The runtime** — apps (name, frontend/backend role, port), FE→BE dependencies,
   infrastructure (e.g. mongodb, mysql). A simple presentation (an editable list).
6. **Claude's extensions (secondary)** — add **MCPs** (e.g. postgres, mysql), **plugins**,
   **skills** and **custom commands** (a name + a description); the commands become available
   through **auto-complete in the chat** (see §6).
7. **The configuration chat** — a **chat screen with Claude** to define the **workspace's
   rules** (e.g. "do not merge `develop` into the feature branch"), the **workflow rules** and
   the **project's context**. Claude (mocked) may ask **questions** and consolidate the rules in
   a side panel as it goes.

The Home/listing allows: editing, **re-testing connections**, **updating credentials**
(tokens/keys), adding/removing repositories, activating/deactivating/deleting.

### 5. Development — the demand list

On choosing "Develop" in a workspace, list **the Dev's demands** (mocked Jira cards). Each card
shows **two statuses**:
- **The status in Jira** (e.g. To Do, In Progress, Code Review, Done…).
- **The status in DOP**: `new` | `doing` | `done` | `delivered` (a distinct badge).
  - `new` = it has not started in DOP · `doing` = Claude+the Dev working · `done` = the PR is
    made and it is considered finished · `delivered` = the PR was merged and the pipeline ran.

Simple filters (by DOP status, by Jira status, a search by key). Clicking the card → the
execution screen.

### 6. The demand's execution/detail screen (the product's core)

A layout in **3 areas** (responsive; side by side on wide screens):

**(A) The chat with Claude** (the main column)
- The Dev ↔ Claude conversation (mocked). Messages with markdown, code blocks, and "Claude's
  actions" (e.g. "I ran `dop demand-init OG-123`", "I created branch X").
- **Auto-complete of custom commands**: on typing `/`, suggest the commands configured in the
  workspace (step 6) + the default commands.
- An input box with a send action; a "Claude is working…" indicator.

**(B) The demand's stage wizard** (on the side) — **static stages (the MVP)**, showing the
**current stage**, the ones **already run** (✓) and the **next ones**. The 7 stages:

1. **Start the demand** — reading the Jira card **through the MCP**; the human gives the
   **jira-key** through the chat.
2. **Contextualisation** — Claude and the human interact; Claude does a **forensic reading**,
   looks for what it needs in the source code; the human gives the data needed; Claude
   **assembles the context**.
3. **The plan** — Claude assembles the **development and test plan**.
4. **Running the plan** — the implementation + unit tests + e2e tests; Claude **invokes DOP
   through the CLI**, which **creates the branches** (as it already works today).
5. **Running the tests** —
   - **5.1 Unit tests:** it runs them; it **adjusts the tests** if they fail through a test
     error; it **adjusts the source code** if the tests are right but the implementation fails.
   - **5.2 e2e tests:** it runs them; it **adjusts repeatedly** (the tests and/or the code)
     until they **pass**.
6. **Human validation** — the human does a **functional test**, interacts with Claude (which may
   or may not need to adjust) and finally **approves** the change.
7. **Finalisation** — Claude invokes **DOP** for **commit + push + PRs**, assembles a **simple
   .txt message** with the **list of PRs** (without much detail, as today), **finishes the
   demand** and **moves the card to the next stage** (the card's stages/filters are defined
   through the chat on the demand).

Each stage has a state: `pending` | `running` | `done` | `blocked`. Show progress and allow
clicking a stage to see its summary. *(A note: marking a stage as done may be an action of
Claude's or of the Dev's — treat it as data coming from the API.)*

**(C) The dossier + logs** (tabs or a bottom panel) — a **lean** presentation:
- **Git:** the repos affected, the branches created, the commits.
- **PRs:** sent and **merged**, **who approved**, the **conflicts**.
- **Files handled:** plans, contexts, **ADRs**, source code created/changed.
- **Tests:** the unit and **e2e** tests created, with their result (`success`/`fail`/`skipped`)
  and **progress bars** in the test stage. Do **NOT** implement the live Playwright view now (it
  is left for another phase) — only status/count/progress.
- **Time:** start, end, time spent (per demand; optionally per stage).
- **Allure:** only a **placeholder** "Allure report" (no integration now).
- **Logs (real time, mocked):** three selectable sources — **(a) the applications**, **(b) the
  tests (unit/e2e)**, **(c) the infrastructure containers** (mysql/mongo/allure). Simulate
  streaming (new lines appearing); reachable by a click.

### 7. The data model (TypeScript — in `lib/api/types.ts`)

Define and use these types (adjust names/fields if it improves clarity, keeping the intent).
Create realistic fixtures in `lib/mocks/`.

```ts
type WorkspaceStatus = 'draft' | 'active' | 'inactive' | 'deleted';
type GitProtocol = 'http' | 'https' | 'ssh';
type DopStatus = 'new' | 'doing' | 'done' | 'delivered';
type StageStatus = 'pending' | 'running' | 'done' | 'blocked';
type TestStatus = 'running' | 'success' | 'fail' | 'skipped';

interface RepoConfig {
  id: string; name: string; remoteUrl: string; protocol: GitProtocol;
  credentialRef?: string;                 // a reference (never the secret itself)
  baseBranch: string; prTargets: string[]; flowRules?: string;
}
interface TaskManagerConfig { provider: 'jira'; baseUrl: string; project: string; }
interface RuntimeApp { name: string; role: 'frontend' | 'backend'; port: number; dependsOn?: string[]; }
interface ClaudeExtensions {
  mcps: { name: string; kind: string }[];   // e.g. { name:'pg', kind:'postgres' }
  plugins: string[]; skills: string[];
  commands: { name: string; description: string }[];
}
interface Workspace {
  id: string; name: string; root: string; status: WorkspaceStatus;
  gitProvider: 'azure_devops';
  repos: RepoConfig[]; taskManager: TaskManagerConfig;
  runtime: { apps: RuntimeApp[]; infra: string[] };
  claudeExtensions: ClaudeExtensions;
  rules: string[];                          // the consolidated rules (the chat step)
  context: string;                          // the project's context
}
interface Stage { key: string; title: string; status: StageStatus; summary?: string; startedAt?: string; finishedAt?: string; }
interface PullRequest { id: string; repo: string; sourceBranch: string; targetBranch: string; url: string; merged: boolean; approver?: string; hasConflict: boolean; }
interface FileTouched { path: string; kind: 'plan' | 'context' | 'adr' | 'source' | 'test'; change: 'created' | 'modified'; }
interface TestResult { name: string; type: 'unit' | 'e2e'; status: TestStatus; }
interface DemandDossier {
  repos: string[]; branches: string[]; commits: number;
  prs: PullRequest[]; files: FileTouched[]; tests: TestResult[];
  startedAt?: string; finishedAt?: string; elapsedSeconds?: number;
}
interface ChatMessage { id: string; author: 'dev' | 'claude'; text: string; at: string; actions?: string[]; }
interface LogLine { source: 'app' | 'test' | 'infra'; service: string; line: string; at: string; }
interface Demand {
  id: string; jiraKey: string; title: string; assignee: string;
  jiraStatus: string; dopStatus: DopStatus;
  stages: Stage[]; dossier: DemandDossier; chat: ChatMessage[];
}
```

### 8. The API's interface (in `lib/api/client.ts`) — the mock implements it

```ts
interface DopApi {
  listWorkspaces(): Promise<Workspace[]>;
  getWorkspace(id: string): Promise<Workspace>;
  saveWorkspace(ws: Partial<Workspace>): Promise<Workspace>;   // an upsert per step
  testConnection(kind: 'git' | 'jira' | 'runtime', payload: unknown): Promise<{ ok: boolean; message: string }>;
  listDemands(workspaceId: string): Promise<Demand[]>;
  getDemand(workspaceId: string, demandId: string): Promise<Demand>;
  sendChatMessage(demandId: string, text: string): Promise<ChatMessage>;   // the mock answers as "claude"
  streamLogs(demandId: string, source: LogLine['source']): AsyncIterable<LogLine>; // or a callback; simulate streaming
}
```

The `mockClient` has to simulate latency (200–800ms), plausible answers from Claude, and a
"streaming" of logs (new lines every ~1s). Include ~3 workspaces and ~8 demands in varied states
(including demands that ask for the Dev's attention).

### 9. Out of scope (do NOT do it now)

- The **live** view of the e2e tests (Playwright in the browser) — another phase.
- A real backend, authentication, multi-user, deployment.
- A real integration with Jira/Azure/Allure (all mocked).

### 10. Acceptance criteria

- Complete navigation between all the routes of §3.
- A working wizard with a save per step and editing; "test the connection" buttons (mocked).
- A demand list with a **double status** and filters.
- An execution screen with a **chat + a 7-stage wizard + the dossier + the logs** (the logs
  simulating streaming; 3 sources).
- A minimalist, responsive UI, a light/dark theme, no real data.
- The screens depend **only** on the `DopApi` interface (a pluggable mock).

---

## Notes for the team (do not send to Replit)

- The `DopApi` interface and `types.ts` are the **preliminary contract** Claude will use when
  building `dop-api`; keeping them aligned avoids rework at integration time.
- When the API exists, Claude swaps `mockClient` for an `httpClient` that implements `DopApi` —
  the screens do not change.
- The live view of the e2e tests (D11) and the dynamic stage process are post-MVP evolutions,
  already recorded in the PRD.
