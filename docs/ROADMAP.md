# The DOP platform — decomposition and state

The project's index. Every spec points here instead of repeating the scope.

## Subprojects

| | Subproject | Decides | State |
|---|---|---|---|
| **SP-0** | Identity, accounts and tenancy | Who the user is, what an account is, how ownership and isolation work, where the integrations live, the account → workspace → project hierarchy | ✅ designed |
| **SP-4** | The work model: specs and autonomy | What the platform does; what replaces the stages; where the human decides, approves and gives context | ✅ designed — subsystems (ADRs 0006–0012) + **the core closed by ADR-0014** (a dynamic, typed and inheritable flow); P-8 remains (the criteria's syntax) |
| **SP-1** | Component and repository topology | Which components exist and each one's role | ✅ designed — ADRs 0016–0020 + the backend architecture spec |
| **SP-3** | The domain model and persistence | Workspace, project, card, artifact, event; the database | ✅ decided — ADR-0018/0019 + the schema in the backend spec |
| **SP-2** | Contract and protocols | The contract's source of truth; REST, gRPC and streaming | ✅ decided — ADR-0017 (proto); the `.proto` files remain to be written |
| **SP-5** | Runtime, environment and IDE | The terminal, parallel execution, deployment | ⬜ |
| **SP-6** | Integration with Claude | The agent, the chat as a command channel | ⬜ |

**The order:** SP-0 → SP-4 → SP-1 → SP-3 → SP-2 → SP-5 → SP-6.

SP-0 is the furthest upstream: everything else operates inside an account. SP-4 comes right
after because it defines *what the platform does* — SP-3 and SP-2 exist to serve that, and
deciding a schema or a contract before would be deciding in the dark.

## Documents

| Document | Answers |
|---|---|
| [`GLOSSARY.md`](GLOSSARY.md) | What each word means |
| [`adr/`](adr/) | Why each structuring decision was taken |
| [`superpowers/specs/`](superpowers/specs/) | What each subsystem is |
| [`superpowers/plans/`](superpowers/plans/) | In which order it is built |

## SP-0's phasing

**A complete model from day one, a partial construction.**

**Born in the schema now, even with no screen:** `Account` with `kind`, `Membership` with a
role, `Integration` with an `accountId`, the grants table and `Invite`. Every domain entity
carries account, workspace and project from the first migration. The edge authenticates every
call and resolves an active account from the first route.

**Built now:** authentication by the four methods, an automatic personal account at sign-up,
personal integrations with the `SecretStore` behind the port and both adapters, and the
workspace → project hierarchy.

**Left to the next phase:** creating an organization, the autofill by company registration
number, inviting and linking members, editing roles and grants, domain verification, the
organization credential.

Phase 2 comes in **with no migration** — that is what justifies modelling everything now.
Phase 1 already exercises multi-tenancy for real, because every query filters by account from
the start; the account simply is always personal.

## The agreed order

1. Finish the structure/architecture — the **agent's tools** (the piece missing for the
   platform to execute instead of only modelling) and the **cockpit**. The provider focus is
   **Anthropic**; the multi-provider port (ADR-0022) stays and the OpenAI adapter exists, but
   with no investment now. Next, **hosted Claude Code** (P-25) as the second front.
2. **A discussion** before the user stories: communication (P-11), sandbox provisioning (P-24)
   and the agent's account/billing model (P-23).
3. User stories.

## Cross-cutting open items

Raised in SP-0's review, each requiring its own decision and a probable ADR:

| # | Open item | Where it hurts |
|---|---|---|
| ~~P-1~~ | **Resolved by ADR-0006** — auditing is a projection of the demand's event log | — |
| P-2 | **The integration's `status` transitions** — who detects `expired`, how often, what happens to work in progress | SP-0 integrations + SP-5 execution |
| P-3 | **Data protection law** — retention, deletion and residency, with personal and company registration numbers in scope | Cross-cutting; it affects account deletion |
| ~~P-4~~ | **Resolved** — the control plane on Cloud Run; the execution plane on a cluster (GKE/k3s). The backend architecture spec §1 | — |
| P-5 | **The cost of the *workspace → project* renaming** in code, routes, i18n, mocks and documentation | Execution; it becomes a task in a plan |
| P-6 | **Recovering an unverified orphaned organization** — with no proven domain, there is no evidence available to claim ownership | SP-0 identity |
| P-7 | **Calibrating the ModelRouter** — ADR-0011's task→(model, effort) table is born as an informed guess; it is calibrated with real telemetry (F-7) and with the cost events' cache fields | ADR-0011/0012 |
| P-8 | **The syntax of the executable criteria** inside the `spec` artifact — ADR-0007 fixes the requirement and ADR-0014 fixes where they live | the workflow spec |
| P-9 | **⭐ External sharing of flows** (between accounts / a community catalogue) — **strategic**: it waits, it does not sleep; a candidate engine for popularizing the platform. Revisit every planning cycle | ADR-0014 §7 |
| ~~P-11~~ | **E-mail delivered — ADR-0025.** The trigger separated from the channel, a `Mailer` with SendGrid and SMTP, an attention digest with a delay. **SMS and push stay out**: they come in as ports of their own (`Pusher`, `SMSer`) when they exist, because channels do not have the same shape | — |
| P-12 | **The `ctx` field with no effect in the protos** — every request declares `CallContext ctx = 1`, and the server ignores it: it authorizes only by the metadata (ADR-0017, convention 5). A contract that declares a field with no effect teaches the wrong thing to whoever reads it. Remove it in a dedicated pass, reserving number 1 | ADR-0017; it touches all 10 protos |
| P-13 | **The Storage emulator hangs with `application/json`** and falls over at around 16 concurrent operations — keeping JSON in the object store locks up the local environment. Found by the ObjectStore contract suite; it is not the adapter's defect (the file one passes all 13 subtests). Decide between waiting for a fix in the emulator, writing JSON with another Content-Type, or using `uploadType=multipart` | dop-infra/docs/local-environment.md |
| ~~P-14~~ | **Resolved** — two adapters (GitHub and GitLab) with a contract suite, and the provider resolved PER REPOSITORY (ADR-0013), not at boot | — |
| ~~P-15~~ | **Resolved** — the launcher checks the isolations at boot and refuses to come up without knowing; the idle sweep is wired to the scheduler | — |
| P-16 | **An artifact per stage** — with no artifact storage, the spec stays out of the context package (the package loses the spec, it does not become incorrect) and `ValidateFlow` cannot really require an artifact | ADR-0014; the workflow/demand/knowledge domains |
| P-17 | **OUR OWN Secret Manager emulator** — today we use a community one (13 stars, a single maintainer), pinned by digest and isolated by a NetworkPolicy. The owner's decision: unblock now, swap for ours later. Written from googleapis' official protos, ~200 lines, as we already do with the Firebase emulator's image | dop-infra |
| P-18 | **Authenticating the caller between the BFF and the core** — the core trusts the metadata's `x-actor-id`/`x-account-id` (ADR-0016). The NetworkPolicy makes the assumption hold, but that is not the same as authenticating. Sandboxes run agent code in the same cluster | dop-core + dop-infra; ADR-0016 |
| ~~P-19~~ | **Partly resolved** — `ListFindings`, `Contributors`/`Origins`, `dropped` and `currency` entered the contract. What remains is the **query for the evidence of green**: `Evidence.Missing()` exists in the domain, but `DeliveryService` does not expose it, so the PR's screen does not show the package ADR-0007 §4 requires | dop-core |
| ~~P-20~~ | **Resolved** — the four workarounds are out; the `dropped` one was BROKEN, not working | — |
| ~~P-21~~ | **Resolved** — the box at the edge, reusing the existing SSE; `AttentionUpdate` gained an `event_id` for the resume | — |
| ~~P-22~~ | **Resolved** — it became a TEST: it sweeps `app/` for a vault, a provider key and a model SDK | — |
| P-23 | **⭐ Whose the agent's account is — and who pays for what.** **Anthropic's terms VERIFIED on 2026-08-31** (`code.claude.com/docs/en/legal-and-compliance`), and they close half the options: (a) **OAuth on the user's account — FORBIDDEN.** *"Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users"*, and *"developers may not collect, store, or intermediate Claude.ai credentials or session tokens"*. (b) **Reselling through DOP's enterprise account — FORBIDDEN.** *"Customers may not pay for, resell, or intermediate Claude usage on their end users' behalf. Each end user must authenticate with their own Anthropic API key, Claude subscription plan credentials, or 3P inference provider credential"*. (c) **BYOK — ALLOWED, and described almost literally as what we have already built**: *"configuring an API key in a development environment, secrets manager, or machine image for use by the customer's own authorized users — provided the resulting usage is billed to the key owner"*. (d) **Hosting Claude Code in the sandbox with the user signing in with their own subscription — ALLOWED with conditions**: an UNMODIFIED binary, no authentication method removed, no paying/reselling/intermediating, and a branding restriction (not using the name in our screens). **The OTHER vendors' terms still have to be checked** before generalizing | **a discussion**, before the user stories |
| ~~P-24~~ | **Decided — ADR-0024.** A microVM per DEMAND (not per thread: a demand's threads are agents of the same account, and the hard boundary is between accounts and demands), with **one shared worktree**, and an **ephemeral pod per verification run**. Only the provisioning TRIGGER stays open — today it is an explicit call | — |
| P-25 | **⭐ Claude Code hosted in the sandbox** — the second front decided, after the API path. The sandbox runs the binary and the user signs in with their OWN subscription, through Anthropic's flow: it solves the "paying twice" problem without intermediating a credential. The terms' conditions, verified: an **unmodified** binary, no authentication method removed or restricted, no paying/reselling/intermediating usage, and a **branding restriction** — we may say in plain text that the product runs Claude Code, but not use the name or the logo in our product's name, in our logo, or in a way that suggests a partnership. An architectural consequence: the **tool loop becomes Claude Code's**, not ours — the two execution models coexist, and that is what allows comparing in practice which one serves better | after the API path |
| P-26 | **The provisioning trigger** — what was left of P-24. Today the sandbox comes up on an explicit call. The option discussed was provisioning when the demand enters a stage whose TYPE requires execution (`implementation`, `test`), which would mean a demand parked at the spec's approval never lights up an environment | ADR-0024 |
| P-27 | **The ephemeral verification environment** — ADR-0024 decided it, it remains to be built: a pod per run, built from a COMMIT, with its own Service and Ingress and a life lasting only the test. It implies the agent commits before verifying, and `EndpointURL` needs an address per RUN — today it is per demand, and two verifications of the same demand would collide | dop-core + dop-infra |
| P-28 | **Validating the `hardware` isolation** — k3d has no Kata RuntimeClass, so the suite only proves `namespace`. The refusal is honest today (asking for hardware where there is none gives an error, not a lesser isolation), but the microVM path has never been exercised | dop-infra |
| P-29 | **⭐ Reaction to an event as DATA, not as code** — today each consumer decides in Go what to do when an event arrives (`attention.Apply` is a `switch`). The product owner wants the reactivity to be a DATA STRUCTURE mapping event → action(s), and the actions not to be only e-mail: triggering other processes too. The discussion is deliberately deferred; what has already been agreed is that the communication is born in the shape that change will require — the decider separated from the executor, an action addressable by name, and an idempotency key derived from (event, rule, action) and not from the event alone | **a discussion**, after communication |
| ~~P-30~~ | ~~**The invite carries no acceptance link**~~ — **RESOLVED** by ADR-0026: the invite stopped having a token. The row's `id` travels in plain text because on its own it grants nothing — acceptance requires the session's VERIFIED e-mail to be the invite's. The e-mail now carries `/invites/{invite_id}`. It closed an independent hole into the bargain: before, any authenticated user holding the link got into the account | ✅ ADR-0026 |
| P-31 | **A subject swapped between notification kinds is not detectable** — two texts written by people, swapped with each other, pass any test. The redundancy that would solve it would be the subject living INSIDE the template, which SendGrid does not allow while it keeps the subject separate from the body. It stays as a known limit | dop-core |
| P-32 | **There is no invite acceptance path** — `identity.AcceptInvite` exists and is covered, but nothing reaches it: the BFF exposes no route and the cockpit has no `/invites/:id` screen for the e-mail to point at. Today the invite's link leads to a 404. It needs a route in the BFF, a screen in the cockpit and the two refusals with their own text (an unverified e-mail × somebody else's invite) | dop-api + dop-app; ADR-0026 |
| P-10 | **Exploring the Overview** — the final shape of the level above the task header; already defined: a Project architecture item (general analyses on demand: stacks, integrations, strengths/weaknesses, improvement proposals in diagrams and charts) | the navigation spec §3 |
