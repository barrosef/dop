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

**Built now:** authentication by the four methods, the **second factor** with its three
verifiers (TOTP, e-mail, SMS — ADR-0027), an automatic personal account at sign-up, personal
integrations with the `SecretStore` behind the port and both adapters, and the workspace →
project hierarchy.

**Done on 2026-09-02:** the second factor end to end — the `secondfactor` domain, RFC 6238 TOTP
written in the standard library, the `SMSer` port with two adapters and a contract suite, the
step-up gate on four sensitive operations, the contract, the edge and the cockpit's screens.
Along with it, the invite's acceptance path (P-32) and the account screen (members, invites,
creating an organization).

The second factor is in phase 1 on purpose: it is a security gate, and a gate added later has to
be retrofitted onto sessions and sensitive operations that were already written without it. The
`require_second_factor` policy per account is modelled now and enforced when organizations
arrive.

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

## 2026-09-03 — the three rounds before the user stories

Decided with the owner, in this order:

| Round | What goes in it |
|---|---|
| **1 — now** | **P-27** (decided: one address per demand; parallelism inside a demand QUEUES) and **P-16** (decided: the project's documents indexed and its storage mounted as a volume in that project's runners). Both turned out to depend on **P-38** — see below |
| **2 — a conversation** | **P-18** (authenticating the caller between the BFF and the core — the owner asked for it to be explained from scratch) and **P-23** (whose the agent's account is; review the options again) |
| **3 — before the user stories** | **P-29** (reaction to an event as DATA — leaving it for later costs a cross-cutting debt) and **P-26** (provisioning has to be INTELLIGENT: something decides whether to provision at all) |

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
| ~~P-12~~ | **Resolved on 2026-09-02.** The field left the 12 protos with number 1 reserved, `CallContext` left `common.proto`, and the BFF stopped building one (77 call sites, plus the 69 `ctx = auth_ctx.get()` locals that existed only to feed it). The two tests that asserted the context travelled in the BODY now assert it does not — the guard against it coming back. It had already spread by itself into `secondfactor.proto`, written the day before | ✅ ADR-0017 |
| P-13 | **The Storage emulator hangs with `application/json`** and falls over at around 16 concurrent operations — keeping JSON in the object store locks up the local environment. Found by the ObjectStore contract suite; it is not the adapter's defect (the file one passes all 13 subtests). Decide between waiting for a fix in the emulator, writing JSON with another Content-Type, or using `uploadType=multipart` | dop-infra/docs/local-environment.md |
| ~~P-14~~ | **Resolved** — two adapters (GitHub and GitLab) with a contract suite, and the provider resolved PER REPOSITORY (ADR-0013), not at boot | — |
| ~~P-15~~ | **Resolved** — the launcher checks the isolations at boot and refuses to come up without knowing; the idle sweep is wired to the scheduler | — |
| ~~P-16~~ | **BUILT on 2026-09-03 — ADR-0028.** The project's knowledge is its root repository, hosted by the platform: `ProjectRepository` port (8 guarantees, two adapters, one contract suite), a git server (bare repos + `git http-backend` + per-demand HMAC tokens + push fan-out + mirror), the sandbox cloning it at `/project` read-write with the token as a projected file, and the sandbox's guarantees rewritten to 18–23 — green on Docker, and on Kubernetes. `knowledge` commits the text of every artifact and regenerates the manifest on every push; a push is an event. What is left is the surface: the cockpit's view of the shelf, and P-41 | ✅ ADR-0028 |
| P-17 | **OUR OWN Secret Manager emulator** — today we use a community one (13 stars, a single maintainer), pinned by digest and isolated by a NetworkPolicy. The owner's decision: unblock now, swap for ours later. Written from googleapis' official protos, ~200 lines, as we already do with the Firebase emulator's image | dop-infra |
| P-18 | **DECIDED on 2026-09-03 — solution F (hybrid).** The core stops trusting text and verifies a SIGNATURE on every call; the token's type depends on who calls: a call with a person carries the user's JWT, which the core verifies through the `IdentityProvider` port it already has (`VerifyToken`, the Firebase adapter and the forged-token contract suite are built); a machine call — worker, sched, launcher, and the BFF's own `EnsureUser` before an actor exists — carries an assertion signed by the platform, one key per caller. One rule in the interceptor: **no valid signature, no actor**. The NetworkPolicy stays: it does not replace, it adds. Verified on the day: a loose pod gets `BLOCKED_9090` and `REACHED_9091` — today's guarantee is a deployment property, which is exactly the argument. Build order: the JWT first (cheapest, closes the person's path, machinery exists), the assertion after. Canvas of the discussion: [A fronteira de confiança do núcleo](https://claude.ai/code/artifact/f863766d-b943-49b2-a674-66bfd9012b31) | ✅ decided; ADR + build pending |
| ~~P-19~~ | **Partly resolved** — `ListFindings`, `Contributors`/`Origins`, `dropped` and `currency` entered the contract. What remains is the **query for the evidence of green**: `Evidence.Missing()` exists in the domain, but `DeliveryService` does not expose it, so the PR's screen does not show the package ADR-0007 §4 requires | dop-core |
| ~~P-20~~ | **Resolved** — the four workarounds are out; the `dropped` one was BROKEN, not working | — |
| ~~P-21~~ | **Resolved** — the box at the edge, reusing the existing SSE; `AttentionUpdate` gained an `event_id` for the resume | — |
| ~~P-22~~ | **Resolved** — it became a TEST: it sweeps `app/` for a vault, a provider key and a model SDK | — |
| P-23 | **⭐ ROUND 2 — reopen and review the options.** **Whose the agent's account is — and who pays for what.** **Anthropic's terms VERIFIED on 2026-08-31** (`code.claude.com/docs/en/legal-and-compliance`), and they close half the options: (a) **OAuth on the user's account — FORBIDDEN.** *"Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users"*, and *"developers may not collect, store, or intermediate Claude.ai credentials or session tokens"*. (b) **Reselling through DOP's enterprise account — FORBIDDEN.** *"Customers may not pay for, resell, or intermediate Claude usage on their end users' behalf. Each end user must authenticate with their own Anthropic API key, Claude subscription plan credentials, or 3P inference provider credential"*. (c) **BYOK — ALLOWED, and described almost literally as what we have already built**: *"configuring an API key in a development environment, secrets manager, or machine image for use by the customer's own authorized users — provided the resulting usage is billed to the key owner"*. (d) **Hosting Claude Code in the sandbox with the user signing in with their own subscription — ALLOWED with conditions**: an UNMODIFIED binary, no authentication method removed, no paying/reselling/intermediating, and a branding restriction (not using the name in our screens). **The OTHER vendors' terms still have to be checked** before generalizing | **a discussion**, before the user stories |
| ~~P-24~~ | **Decided — ADR-0024.** A microVM per DEMAND (not per thread: a demand's threads are agents of the same account, and the hard boundary is between accounts and demands), with **one shared worktree**, and an **ephemeral pod per verification run**. Only the provisioning TRIGGER stays open — today it is an explicit call | — |
| P-25 | **⭐ Claude Code hosted in the sandbox** — the second front decided, after the API path. The sandbox runs the binary and the user signs in with their OWN subscription, through Anthropic's flow: it solves the "paying twice" problem without intermediating a credential. The terms' conditions, verified: an **unmodified** binary, no authentication method removed or restricted, no paying/reselling/intermediating usage, and a **branding restriction** — we may say in plain text that the product runs Claude Code, but not use the name or the logo in our product's name, in our logo, or in a way that suggests a partnership. An architectural consequence: the **tool loop becomes Claude Code's**, not ours — the two execution models coexist, and that is what allows comparing in practice which one serves better | after the API path |
| P-26 | **The provisioning trigger — ROUND 3.** The owner's framing: provisioning has to be **intelligent** — a mechanism decides whether there will be provisioning at all, rather than a rule fixed in code. Today the sandbox comes up on an explicit call. The option previously discussed (provision when the demand enters a stage whose TYPE requires execution) is one input to that decision, not the decision itself: a demand parked at the spec's approval must not light up an environment, and a demand that only needs to read might not need one either | **round 3**; ADR-0024 |
| ~~P-27~~ | **Decided on 2026-09-03: the address stays PER DEMAND.** ADR-0024 had foreseen a pod per run with its own Service and Ingress; the owner cut it — when a demand needs parallelism, the execution **queues**. It buys simplicity in exchange for latency inside one demand, and it removes the schema change `EndpointURL` would have required. What is left is not the address: it is that **nobody runs a verification** — `RecordVerification` records a run produced elsewhere, and no component launches one. That went into P-38 | ✅ decided; the runner is in P-38 |
| P-28 | **Validating the `hardware` isolation** — k3d has no Kata RuntimeClass, so the suite only proves `namespace`. The refusal is honest today (asking for hardware where there is none gives an error, not a lesser isolation), but the microVM path has never been exercised | dop-infra |
| P-29 | **⭐ Reaction to an event as DATA, not as code — ROUND 3, today, before the user stories.** The owner's reason for not postponing it: it is a CROSS-CUTTING debt, and leaving it for later costs dearly — the whole of epic 10 would be written against a `switch` and rewritten afterwards. Today each consumer decides in Go what to do when an event arrives (`attention.Apply` is a `switch`). What is wanted is a data structure mapping event → action(s), and the actions not to be only e-mail: triggering other processes too. Already agreed: the decider separated from the executor, an action addressable by name, and an idempotency key derived from (event, rule, action) and not from the event alone | **round 3**, today |
| ~~P-30~~ | ~~**The invite carries no acceptance link**~~ — **RESOLVED** by ADR-0026: the invite stopped having a token. The row's `id` travels in plain text because on its own it grants nothing — acceptance requires the session's VERIFIED e-mail to be the invite's. The e-mail now carries `/invites/{invite_id}`. It closed an independent hole into the bargain: before, any authenticated user holding the link got into the account | ✅ ADR-0026 |
| P-31 | **A subject swapped between notification kinds is not detectable** — two texts written by people, swapped with each other, pass any test. The redundancy that would solve it would be the subject living INSIDE the template, which SendGrid does not allow while it keeps the subject separate from the body. It stays as a known limit | dop-core |
| ~~P-32~~ | **Resolved on 2026-09-02.** The core gained `ListInvites` and `GetInvite` (the preview, which does NOT carry the invitee's e-mail), the BFF gained `/invites`, `/invites/{id}`, `/accept`, the revocation and `PATCH /members/{id}`, and the cockpit gained `/invites/:id` — outside the shell, because whoever opens an invite may not be a member of any account yet. The two refusals are different screens: a 412 sends the person to confirm their e-mail, a 403 says the invite is not theirs, and neither reveals the address | ✅ |
| P-36 | **The QR code of the TOTP enrolment** — rendering one would mean a new dependency in the authentication path, which is the same argument that kept the TOTP implementation dependency-free (ADR-0027). Today the screen shows the key for manual entry, grouped in fours, plus the `otpauth://` link, which opens the app directly on a phone. The two ways out: accept a dependency after a review, or write the encoder (Reed-Solomon, ~300 lines). It is a real UX regression against what people expect, and it is deliberate | dop-app |
| P-33 | **The SMS provider and the second adapter of `SMSer`** — the port is born with ADR-0001's discipline (two adapters + a contract suite); WHICH second provider, and at what per-message cost, is open. The abuse ceiling it brought along was **closed on 2026-09-02**: 60 s between messages and 5 per hour per factor, with the floor hanging off the PENDING challenge so whoever answers correctly is not made to wait for having succeeded. What is left is the commercial decision | ADR-0027; dop-core + dop-infra |
| P-34 | **Accepting a second factor asserted by the identity provider** — somebody with 2FA on their Google account does ours as well, and that is real friction. Recognizing the assertion (`amr`, `acr`) means normalizing it in the `IdentityProvider` port, in every adapter, and letting the account's policy decide whether it counts. Rejected in v1 to keep a single ruler; worth revisiting with usage data | ADR-0027; ADR-0001 |
| ~~P-37~~ | **Resolved on 2026-09-02.** Unlinking a member and editing resource grants now have a screen. The rule nobody had written — what happens to what the person created — was settled: it **stays with the account** (a resource belongs to the account; `created_by` keeps the trail of who made it), what goes away with the membership are the **grants**, because a grant outliving the membership is access with nothing to justify it. The order is the sweep first, the removal after: a failure in the sweep removes nothing. A personal account's membership is not removable — that would be deleting the user (P-3) | ✅ |
| P-35 | **The second factor in the local environment** — TOTP runs identically everywhere (it is pure code), e-mail goes through the mailer's dry run, and SMS has no emulator: the adapter prints the code. The path is exercised, the delivery is not. Decide whether that is enough or whether a fake gateway is worth it | ADR-0027; dop-infra |
| P-38 | **⭐ THE SANDBOX IS EMPTY — nothing puts content in, and there is no toolbox.** Found on 2026-09-03 while sizing P-16 and P-27, and it is bigger than either. Three absences that are the same absence: (1) **nothing populates the workspace** — there is no clone, no fetch, no checkout anywhere in the core, only comments mentioning them; (2) the **devbox image has no `git`, no `bash`, no `curl`** — its own Dockerfile records it as a TODO, "the agent has a shell and nothing else"; (3) **nobody launches a verification** — the record exists (`VerificationRun`), the runner does not. The lifecycle (launch/suspend/resume/destroy/exec) is complete and covered by the contract suite, and the tool loop reaches it: what is missing is the CONTENT. The `SandboxLauncher` port has no write path either — deliberately, since `Exec` has no stdin — so getting files in is a port decision, not a script | dop-core + dop-infra; it blocks P-16, the QA epic and any story where the agent works on a repository |
| ~~P-39~~ | **Dissolved on 2026-09-03** by P-16's decision: knowledge as a git repository needs no shared volume, so ReadWriteMany stops being a requirement. Each sandbox holds its own working copy in its own workspace | — |
| ~~P-40~~ | **Answered on 2026-09-03** by P-16's decision: on a git repository the author of the commit IS the attribution ADR-0006 asks for, and the history is the audit trail. What remains is a convention — the commit's author is the THREAD (agent), never a person's identity borrowed by an agent | ADR-0006; goes into the ADR |
| P-41 | **The lessons loop.** Memories are written only by humans through the cockpit; no path turns a demand's findings into the project's memory. "Knowledge collaborated between agents" IS this loop, and it does not exist. A story of epic 09, and the other half of P-16's definition | dop-core; epic 09 |
| P-10 | **Exploring the Overview** — the final shape of the level above the task header; already defined: a Project architecture item (general analyses on demand: stacks, integrations, strengths/weaknesses, improvement proposals in diagrams and charts) | the navigation spec §3 |
