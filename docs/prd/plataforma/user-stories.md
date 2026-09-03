# The DOP platform — features and user stories

> **Status:** A draft for the dev's review · **Date:** 2026-09-01 (rev. 4 — US-5.2 corrected by
> ADR-0026; the organization into epics is under way)
> **The base:** the SP-0 specs (identity, integrations, resources), the workflow spec, the
> navigation spec rev. 2; ADRs 0001–0026
> **Phases:** as per `ROADMAP.md` — **[F1]** is built now; **[F2]** is modelled in the schema
> from now on, built in the following phase.

The features' order follows the real dependency: identity → **resources** (projects consume
resources; without them there is no project) → hierarchy → the cockpit. Organizations and
invites are [F2] and come later in the numbering, even though they exist in the schema from day
1.

---

## 1. Personal sign-up **[F1]**

- **US-1.1** As a dev, I want to sign up with an e-mail and a password.
  - a personal account is created automatically (a handle derived from the e-mail; a collision
    is suffixed)
  - it lands on First use (3 steps)
- **US-1.2** As a dev, I want to sign up with Google, GitHub or LinkedIn in one click.
  - the same effects as US-1.1; the provider is linked to the profile
- **US-1.3** As a dev, I want signing in later through another provider with the same e-mail to
  land in the same account.
  - account linking active from day 1; the links are visible in the profile

## 2. Sign in and the second factor **[F1]**

- **US-2.1** As a dev, I want to sign in through any linked method and land **in the last
  cockpit I was in**, with the demand that was selected.
  - zero intermediate screens; the first sign-in lands on First use
- **US-2.2** As a dev, I want the active account, the project and the selected card to survive a
  sign-out/sign-in and to be shareable by URL.
  - `/:account/:workspace/:project?card=` restores the exact state

> The second factor is the PLATFORM's, not the identity provider's (ADR-0027): one mechanism,
> three verifiers. It is [F1] because a security gate added later has to be retrofitted onto
> sessions and operations already written without it.

- **US-2.3** As a dev, I want to register an **authenticator app** as my second factor, reading
  a QR code and confirming the first code.
  - the `otpauth://` URI is shown ONCE; the seed goes into the vault, never into the cockpit
  - the factor is born `pending` and only becomes `active` after the confirmation
- **US-2.4** As a dev, I want to register my **e-mail** as a second factor and receive a
  6-digit code, valid for 10 minutes and single use.
  - it requires a VERIFIED address — an unproven address is not a second factor
- **US-2.5** As a dev, I want to register my **phone** and receive the code by SMS, with the
  same validity.
  - the number is shown masked (`+55 ** ****-9012`) everywhere it appears
- **US-2.6** As a dev, I want to be asked for the second factor **when I sign in**, and for the
  session to stay stepped up for a while — not on every request.
  - a challenge on every screen is theatre: it teaches people to answer without reading
- **US-2.7** As a dev, I want a fresh challenge **before a sensitive operation**: writing a
  credential, changing a role, inviting, revoking and deleting an account.
  - reading is never gated
- **US-2.8** As a dev, I want **ten recovery codes** at enrolment, shown once, to get back in if
  I lose the factor.
  - kept hashed: the platform cannot show them again, and that is the point
  - without them the recovery path is a conversation with support — the weakest link
- **US-2.9** As a dev, I want to see my registered factors, name them ("iPhone", "work e-mail"),
  add another and revoke one, always with a fresh challenge.
  - revoking the LAST active factor in an account that requires 2FA is refused with a message
- **US-2.10** As a dev, I want a failed attempt to say only that it failed, and a sequence of
  failures to put the factor in a cool-off.
  - five consecutive failures; every attempt is an event on the timeline (ADR-0006)

## 3. The account's resources **[F1 in the core]**

> A resource = the unit of ownership and sharing (ADR-0013): integrations (git, task manager,
> **agent**), skills, human↔agent workflows and git flows. Projects only consume — no credential
> typed into a project.

- **US-3.1 [F1]** As a dev, I want to connect a **git** provider (GitHub, GitLab, self-hosted
  GitLab, Azure DevOps, Bitbucket) through OAuth, a token or an SSH key.
  - the credential only in the SecretStore; the repositories become available to the account's
    projects
- **US-3.2 [F1]** As a dev, I want to connect a **task manager** (Jira, ClickUp, Redmine) so my
  cards flow into the cockpits.
- **US-3.3 [F1]** As a dev, I want to connect an **agent** provider (Claude, Codex, Google Code
  Assist) through my subscription's OAuth or an API key.
  - the models become the router's menu; a BYO cost is measured the same (ADR-0011)
- **US-3.4 [F1]** As a dev, I want to see my integrations' state (`active`, `expired`, `error`)
  and be told in the attention box when one breaks.
- **US-3.5 [F1]** As a dev, I want to keep **git flows** in the account — created by me or
  adopted from the catalogue — versioned, with structural validation and a dry run.
  - they declare: the branch taxonomy per card type, bases, direction, release composition,
    policies
- **US-3.6 [F1]** As a dev, I want to keep versioned **workflows** — composed of typed stages
  (ADR-0014) — creating my own or adopting the platform's default.
  - structural validation at creation; a warning when a `spec` stage is missing
- **US-3.6b [F1]** As a dev, I want a workspace, a project and a demand to **inherit** the flow
  of the level above and to be able to override it with one of their own — always seeing the
  effective flow's origin.
  - the chain platform ◁ account ◁ workspace ◁ project ◁ demand; the demand freezes the version
    when it starts
- **US-3.6c [F2]** As a dev, I want to **promote** a flow I created on a demand to the project,
  the workspace or the account.
- **US-3.6d [F2]** As a dev, I want to keep **skills** as versioned resources.
- **US-3.7 [F2]** As a dev, I want to adopt a resource from the platform's catalogue as a
  versioned copy, seeing the diff when the catalogue evolves.

## 4. Organization accounts **[F2]**

- **US-4.1** As a dev, I want to create an organization with a name and a company registration
  number and use it immediately.
  - autofill of the legal name/address; the creator becomes `owner`; no waiting (ADR-0004)
- **US-4.2** As an owner, I want to verify the domain through a TXT record to unlock automatic
  entry by an e-mail of the domain, the badge and a handle dispute.
- **US-4.3** As a dev, I want to switch between the personal account and organizations in a
  single selector, changing the whole tree with one click.
  - everything you see is the active account's; a request with no active account is invalid
- **US-4.4** As an owner, I want to **require a second factor** of my organization's members.
  - a member with no active factor still signs in and operates their PERSONAL account; what is
    blocked is operating in THIS one
  - the policy may disable SMS: it is the weakest of the three (ADR-0027)

## 5. Invites and access **[F2]**

- **US-5.1** As an owner/admin, I want to invite a dev by e-mail, **composing in the invite** the
  role and the **resource** grants, so they enter with the right access.
  - the roles: `owner`, `admin`, `developer`, `viewer`; a `use`/`manage` grant per resource; no
    defaults
  - it expires in 14 days; revocable while pending; a resend invalidates the previous one
- **US-5.2** As an invitee, I want to accept through the link and land in the organization's
  account.
  - the link carries only the `invite_id` — **there is no token** (ADR-0026): the id on its own
    grants nothing, and that is why it can travel in an e-mail, an event and a projection
  - acceptance requires being signed in **as the invitee**: the session's e-mail VERIFIED and
    equal to the invite's. Without that, any authenticated person holding the link got into the
    account
  - whoever has no account signs up along the way, **with e-mail verification before the
    acceptance** — it is the verification that replaces the token
  - two refusals with their own text: "confirm your e-mail" ≠ "this invite is not yours"; the
    second does NOT reveal who the invite was for (it would become an e-mail oracle)
  - the screen shows clearly which account is being entered
- **US-5.3** As an owner/admin, I want to edit a role and grants at any time, and unlink without
  touching what is the member's own.
  - an invariant: the account is never left without an active `owner`
- **US-5.4** As a developer, I want to see only the resources granted to me when configuring
  projects.
  - revoking `use` does not tear down projects already configured

## 6. Workspaces **[F1]**

- **US-6.1** As a dev, I want to create a workspace with a name, a key, a description and tags —
  and nothing else.
- **US-6.2** As a dev, I want the side tree with search reaching any project in up to 2 clicks.
- **US-6.3** As a dev, I want to edit the workspace in a sliding panel, without leaving where I
  am.

## 7. Projects **[F1]**

- **US-7.1** As a dev, I want to create a project by choosing repositories **from the account's
  integrations** — an already authenticated list, with no credential typed in.
  - the provider belongs to the repository: GitHub and GitLab coexist in the same project
  - resources from different accounts do not mix
- **US-7.2** As a dev, I want to link the task manager's space and the project inside it.
  - the card types come from the provider, dynamic
- **US-7.3** As a dev, I want to **attach resources to the project**: a git flow [F1] — which the
  merge queue, the verification and the branch naming then obey — and a workflow/skills [F2] —
  which parameterize the agents.
- **US-7.4** As a dev, I want to keep the project's rules and consult the accumulated knowledge
  (the index, the memories) in the project's root repository, shown in the cockpit (ADR-0009,
  ADR-0028).
- **US-7.5** As a dev, I want to add/remove repositories and resources later, in a sliding
  panel, without recreating the project.
- **US-7.6** As a dev, I want the project to have a **techlead agent** (ADR-0015), activated when
  there are parallel demands, which detects cross-cutting situations — dependencies, file
  overlap, behaviour interference — plans solutions and **prompts me for decisions in the
  attention box** with ready options.
  - a decision becomes a coordination directive (e.g. "demand 1 cherry-picks from 0's branch when
    it commits")
  - **no demand pauses because of a detected cross-cutting situation** — it carries on as far as
    it can and applies the directive when the condition is met
  - the directives are visible in the Timeline and in the threads of the demands involved

## 8. The cockpit / IDE **[F1]**

> The cockpit's law (the navigation spec rev. 2): a button on the bar opens a **panel** over the
> bar (which shrinks to icons); the **centre** responds to the panel. The task header filters
> everything; the Overview sits above it, outside the bar.

### Navigation
- **US-8.0.1** As a dev, I want to select a card in the strip and see the bar, the panel and the
  centre narrow to that demand; deselecting returns to the project's aggregate.
- **US-8.0.2** As a dev, I want the global attention box (🔔) telling me where I am needed, each
  item leading to the place of the resolution — including pending flow gates.
- **US-8.0.3** As a dev, I want the ⌘K palette to jump to any project/demand without a mouse.
- **US-8.0.4** As a dev, I want the **Overview** in a button above the task header — a view of
  the whole project, immune to the card filter.
- **US-8.0.5** As a dev, I want to click the card's chip and see the provider's original card
  with its artifacts.

### 8.1 Chat (the panel: threads · the centre: the flow's stages)
- **US-8.1.1** As a dev, I want to talk to the main agent and to each subagent in separate
  threads, with their cards and findings (ADR-0010).
- **US-8.1.2** As a dev, I want the centre showing the demand's **effective flow's stage ruler**
  — any flow, rendered by each stage's type (ADR-0014).
  - MD documents with a viewer/source and editing; approval gates visible
- **US-8.1.3** As a dev, I want the **human validation** stage as a checklist tickable item by
  item, generated from the validation plan, with links — being able to reject an item and handle
  it with the agent in the chat.
- **US-8.1.4** As a dev, I want the **finalization** stage with visible steps (commits/pushes →
  PRs → the merge queue → conflicts → the dossier) and a state per step.

### 8.2 Repos (the panel: the git tree · the centre: the content)
- **US-8.2.1** As a dev, I want the full git view: repos → branches → PRs/MRs → files with their
  git status, diffs file by file.
  - branches named according to the attached git flow
- **US-8.2.2** As a dev, I want the **merge queue** per repository — position, re-verification,
  overlaps — and to decide escalated conflicts (ADR-0008).

### 8.3 Infra (the panel: applications · databases · remote services)
- **US-8.3.1** As a dev, I want to see the demand's applications with their state, streaming logs
  and a terminal — **in the application's environment, never in the agent's microVM**.
- **US-8.3.2** As a dev, I want to list the databases and remote services the system uses, with
  their state and logs where available.

### 8.4 QA (the panel: quality groups · the centre: the group's panel)
- **US-8.4.1** As a dev, I want the product's quality groups: acceptance, tests
  (aaa/e2e/integration), coverage, Allure reports, history/flakiness.
- **US-8.4.2** As a dev, I want the code's quality groups: standards & conformance, duplication,
  complexity & debt, dependencies & vulnerabilities.
  - fed by a Sonar-like stack in a container + the agents' findings

### 8.5 Architecture (the panel: artifacts per task and type · the centre: a canvas/viewer)
- **US-8.5.1** As a dev, I want to ask for analyses and **architectural and flow diagrams** of a
  feature tied to the task — "the payment flow that sends an e-mail, decrements stock and goes
  through the queue" — produced by a subagent (a thread in the Chat), rendered in an interactive
  canvas and kept as artifacts of the demand.
- **US-8.5.2** As a dev, I want a **forensic reading** (e.g. of an important hotfix) to yield an
  **opinion**: diagrams + a technical/executive document, grouped in Architecture under that
  task.
- **US-8.5.3** As a dev, I want to browse the architectural artifacts **filtered by the task
  header** — the selected demand shows only its own; with no selection, all the project's, plus
  the map (the ADR-0009 index).

### 8.6 Timeline (the panel: event filters · the centre: the timeline)
- **US-8.6.1** As a dev, I want the demand's timeline — who did what, with which credential —
  filterable by agents, git, gates and cost (ADR-0006/0011/0012).

---

## Outside this draft (recorded so it does not vanish)

- The syntax of the executable criteria inside the `spec` artifact — P-8.
- The declarative format of the **git flow** (the workflow's is already in the spec) and the
  visual editors of both.
- The organization credential (a GitHub App etc.) — [F2], the integrations spec §4.
- Notifications outside the platform (e-mail/push) — future projections of the attention box.
- Recognizing a second factor asserted by the identity provider (P-34) — in v1 somebody with 2FA
  at Google does ours as well, and that is the price of a single ruler.
- WebAuthn/passkeys as a fourth verifier: the three asked for come first, and the domain is born
  with room for a fourth `kind`.
