# The onboarding journey — from "how do you want to enter" to "ready to fly"

- **Date:** 2026-09-20
- **Status:** decisions approved by the owner; spec under review
- **Supersedes:** `2026-09-06-profile-onboarding-design.md` (the five-step
  wizard). Its phone step lives on in the security screen; its tools, social
  networks and referral steps are retired; its plans step is absorbed here.
- **Builds on:** `2026-09-06-account-signup-design.md` (the door — its rules
  stand unchanged), [ADR-0002](../../adr/0002-account-as-unit-of-ownership.md),
  [ADR-0003](../../adr/0003-organization-credential-human-authorship.md),
  [ADR-0009](../../adr/0009-resource-as-unit-of-sharing.md),
  [ADR-0010](../../adr/0010-dynamic-workflow.md) §8 (the platform catalogue),
  [ADR-0022](../../adr/0022-the-core-verifies-its-callers.md)
- **Touches:** `dop-core`, `dop-api`, `dop-app`

## 1. Context — what exists, and why it fell short

The sign-up spec of 2026-09-06 describes **rules**: three ways in, e-mail
linking, verification refused in the core, a personal account born with the
user. All of it is built and holds. What it does not describe is a **journey**,
and the one journey that was specified — the five-step wizard — was blocked on
a backend that was never built. The cockpit therefore has:

- `sign-up.tsx`: one `max-w-sm` card with e-mail, password and two provider
  buttons. Correct, and a door rather than a beginning;
- `onboarding.tsx`: the phone step alone, and **no route leads to it** — after
  sign-up the person lands on `/` with nothing between them and an empty tree;
- no profile editing, no photo beyond what the provider sends, no default
  workspace, no plan, no connection to where the person's code and cards live.

What the providers already deliver, and what they do not:

- **name, e-mail and photo** arrive on every social sign-in (`picture` →
  `Principal.AvatarURL` → `users.avatar_url`). Nothing to add;
- **date of birth does not arrive from anywhere.** GitHub exposes none in any
  scope; Google only through `user.birthday.read`, a sensitive scope that
  requires app verification and a second consent screen. It is asked for on the
  profile step, optional, with its reason on the screen.

What the platform already gives a new account for free: **the default
development flow.** The platform catalogue (`0005_workflow.sql`, seven stages)
is level 0 of the resolution chain, so an account with no flow of its own runs
on it. The journey shows it; it builds nothing.

## 2. Decisions

**D-1. The journey has six moments and one goal: the person leaves it able to
create a project and start.** Entry → profile → workspace → connections → plan
→ ready. Each moment is *explain → act → confirm*; none is a bare form.

**D-2. State lives in the core, never in the browser.** `GET /me/onboarding`
answers where the person is and what is done; the cockpit routes to the next
undone step from any route until the journey is complete, and never again
after. A flag in `localStorage` is lost on another device and forged on this
one. This is the routing exception the wizard spec named (its D-6): the gate
protects nothing, so it stays in the cockpit; the *record* stays in the core.

**D-3. A personal account is born with a personal workspace.** The rule is the
core's, inside `EnsureUser`, idempotent: key `personal`, name from the
person's locale, created together with the personal account and never
duplicated. The journey renames it; it does not create it.

**D-4. Connections are real integrations, not a catalogue of preferences.**
The wizard's "which tools do you use" is replaced by creating the actual
resource (`integration`, category `git` or `task_manager`, the provider's
credential in the vault). The provider list is data served by the API
(`GET /catalog/providers`), with each provider's credential method, required
permissions, whether it needs a base URL, and whether the platform **operates**
it today. GitHub and GitLab are operated; Bitbucket, Azure DevOps, Jira and
ClickUp are registered with their credential and labelled honestly as *not yet
operated*. Nothing in the cockpit knows that list.

**D-5. Connections can be skipped; the closing screen says what is missing.**
The owner's decision. A locked step here would turn a token the person does not
have at hand into a locked door. The "ready" screen lists what is done and
what is not, and its primary action adapts.

**D-5a. Required and optional, stated once.** `profile` and `plan` are
required — they are choices the person can always make. `workspace` is
informative and is done by being seen. `connections` may be skipped (D-5).
`complete` refuses while `profile` or `plan` is undone, and nothing else.

**D-6. A plan is chosen, and it carries no price.** The owner's decision. Free,
Start, Pro and Enterprise from `plan_catalog`, Free pre-selected, the choice
recorded on the personal account (`accounts.plan_key`). No price is shown and
no space is left where one would go; Enterprise leads to a contact action.
Billing is a subsystem of its own and is not started here.

**D-7. The photo is the person's; the logo is the organization's.** Both use
the same mechanism — a signed upload URL from the `ObjectStore`, the bytes
never crossing the BFF, a confirmation call that records the object — on
`users.avatar_url` and on a new `accounts.avatar_url`. The journey uploads the
person's photo (or keeps the provider's). The logo appears on the
create-organization screen, which stays outside sign-up (sign-up spec D-1).

**D-8. Everything the person reads is the API's or the i18n map's.** Provider
permissions, plan taglines, stage names of the default flow, error messages —
none is a string in the cockpit. `RAILS.md` §2 and §6 bind every screen here.

**D-9. Out of the journey, on purpose:** SMS enrolment (offered on the closing
screen as a card that leads to Security), referral (the code stays on the
user; no step), organization creation, billing, GitHub App installation for
organizations (ADR-0003 — a personal account uses a personal token).

## 3. The journey

The step rail is on the left and reflects `GET /me/onboarding`: done, current,
skipped, pending. Every step has a narrative panel that says what the step
does, what the platform will do with the answer, and what skipping costs. The
portal is not visible behind the journey — there is nothing in it yet worth
dimming.

### 0 · Entry — `/sign-up`

Two halves. Left: the promise in three lines — connect your code, bring your
cards, the agent works on your flow. Right: *How do you want to enter?* —
Google, GitHub, e-mail. E-mail expands inline into address and password, with
strength feedback and the policy named **before** it is violated.

Everything the sign-up spec decided holds unchanged: linking on a second
provider (US-5), verification for a password credential refused in the core
(US-2, `412`), the three messages of its §5. The "check your inbox" screen
gains a visible resend countdown and *I typed the wrong address*.

### 1 · Who you are — `/welcome/profile`

Arrives pre-filled from the token: photo, name, e-mail with a *verified* mark.
The person may change the photo (upload with crop, or keep the provider's),
the display name, the personal account's handle (derived from the e-mail,
checked for availability as typed), language and time zone (detected,
confirmed), and a date of birth — optional, with one line saying why it is
asked. Required: name and handle.

### 2 · Your workspace — `/welcome/workspace`

Informative, not a form. *We created **Personal** for you* — renameable — then
what a workspace is (workspace → project → demand), and the default flow drawn
as its seven stages, read from `GET /flows/effective` with the personal
workspace as scope. One line says the flow can be tailored later. Nothing is
required.

### 3 · Where your work lives — `/welcome/connections`

Two groups of tiles from `GET /catalog/providers`: **Code** (GitHub, GitLab,
GitLab self-hosted, Bitbucket, Azure DevOps) and **Tasks** (Jira, ClickUp).
Selecting a tile opens a side panel with that provider's method: the token
kind, the exact permissions to grant (listed, copyable), the base URL when the
provider needs one, and a *test connection* control. Each tile carries the
API's status: *operated today* or *registered — operation coming*. Several
connections may be made; the step may be skipped (D-5).

### 4 · How you want to start — `/welcome/plan`

Four plans side by side from `GET /catalog/plans`, each with name, tagline and
features; Free pre-selected; one must be chosen (D-6). Enterprise's action is
*talk to us*. No price, no gap.

### 5 · Ready to fly — `/welcome/ready`

A checklist: profile ✓, workspace ✓, connections *n* (or *none — your code is
not connected yet*), plan ✓. A card offering to protect the account (SMS
second factor → Security). One primary action: **Create your first project**
when a code connection exists, **Connect your code** when none does; a
secondary *Go to the cockpit*. Completing marks `onboarded_at`; the journey
never appears again.

## 4. The data

One migration in `dop-core`:

```
users        + birth_date date NULL
             + locale text NULL, timezone text NULL
             + onboarding jsonb NOT NULL DEFAULT '{}'   -- {step: done|skipped, ...}
             + onboarded_at timestamptz NULL
accounts     + avatar_url text NULL
             + plan_key text NULL REFERENCES plan_catalog(key)
plan_catalog   key PK, name, tagline, features jsonb, sort, active
provider_catalog
               key PK, category (git|task_manager), name, credential_kind,
               permissions text[], needs_base_url bool, operated bool,
               docs_url, brand_color, sort, active
```

Both catalogues are seeded from `repos/dop-core/seed/catalog.yml` by
`make seed-catalog` — an upsert by key, so editing a tagline is a re-run, not
a migration. Removing an entry sets `active=false`.

Initial provider rows: `github`, `gitlab`, `gitlab_self_hosted` (needs base
URL), `bitbucket`, `azure_devops` in `git`; `jira`, `clickup` in
`task_manager`. `operated=true` only for `github` and `gitlab`.

## 5. The contract

| need | operation | notes |
|---|---|---|
| journey state | `GET /me/onboarding` | steps with status, `personal_workspace_id`, `connections` count, `plan_key`, `complete` |
| record a step | `POST /me/onboarding/steps/{step}` body `{status: done\|skipped}` | the core validates the step name; `skipped` only where D-5 allows |
| finish | `POST /me/onboarding/complete` | sets `onboarded_at`; refused while a required step is undone |
| profile | `PATCH /me` | `name`, `birth_date`, `locale`, `timezone` |
| photo | `POST /me/avatar/upload-url` → `{url, object_ref, expires_at}` · `PUT /me/avatar` body `{object_ref}` | signed PUT from `ObjectStore`; the core validates size and type on confirm |
| logo | the same pair on `/accounts/current/avatar` | organization screens, later |
| personal account | `PATCH /accounts/current` (`display_name`, `handle`) · `GET /accounts/handles/{handle}/availability` | handle rules as today (`NormalizeHandle`) |
| workspace | `PATCH /workspaces/{id}` (`name`) | the personal one is created by the core (D-3) |
| providers | `GET /catalog/providers` | grouped by category, ordered |
| connection | `POST /resources` · `PUT /resources/{id}/credential` | exist today |
| test | `POST /resources/{id}/check` | github/gitlab call the provider (`whoami`); others answer `{operated:false}` with a message |
| plans | `GET /catalog/plans` · `PUT /accounts/current/plan` body `{plan_key}` | Enterprise is a valid choice; the contact is a link |

`MeResponse` gains `avatar_url`, `locale`, `timezone`, `onboarded`.
`AccountSummary` gains `avatar_url` and `plan_key`.

Nothing changes in `Principal`, in the identity adapters or in the
verification contract. `make proto-breaking` must stay green: every addition
is a new field or a new RPC.

## 6. What changes, by repository

**`dop-core`** — the migration and the seed; `EnsureUser` creates the personal
workspace (D-3); `identity` gains profile update, avatar confirm, onboarding
state; `hierarchy` gains workspace rename; `resource` gains `Check` (the
`gitprovider` port already has what `whoami` needs for GitHub and GitLab);
`catalog` is a small new domain (read-only over two tables). Domain tests for
D-3's idempotence, the step validation, `complete` refusing undone required
steps, and `Check` on a non-operated provider.

**`dop-api`** — the routes of §5, use cases first (REST and gRPC share them),
no state, no secret: the signed URL is minted by the core and passed through.

**`dop-app`** — after `fetch-spec` + `codegen`: the six screens, the rail, the
gate from any route (D-2), the provider panel and the crop control. Its own
spec (`repos/dop-app/docs/superpowers/specs/`) is written from this one and is
what the Replit prompt carries — screen by screen, with the generated hooks
named. It is written **after** the contract is on QA, never before.

## 7. Errors the person sees

- **handle taken** — inline, as typed, with a suggestion; never on submit;
- **upload refused** (size, type) — the API's reason, the limits stated on the
  control before the attempt;
- **connection test failed** — the provider's own answer where there is one
  (`401` reads as *the token was refused*), and *this provider is registered
  but not operated yet* where the platform cannot test;
- **complete refused** — the step that is missing, linked;
- the sign-up spec's §5 stands for the entry.

## 8. Testing

- core: domain tests as in §6, no database; a contract-integration test for
  `Check` against the GitHub and GitLab adapters' fixtures;
- BFF: route tests through the use cases, one per operation;
- cockpit: the gate (D-2) against a mocked `GET /me/onboarding` — the one place
  a mock is legitimate, because what is under test is routing;
- end to end on QA before release: Google sign-in → profile → skip connections
  → Free → ready; and the same with a real GitHub token through `Check`.

## 9. What this does not build

Billing and prices; the GitHub App path for organizations; operating Bitbucket,
Azure DevOps, Jira or ClickUp; SMS enrolment inside the journey; referral
rewards; organization creation with logo (the mechanism is here, the screen is
later); editing the catalogues from a screen.

## 10. Open items

1. Plan taglines and feature lists need the owner's words; the seed carries a
   first draft.
2. Upload limits (size, types) — proposed 2 MiB, `image/png|jpeg|webp`.
3. The Enterprise contact — an e-mail or a form; proposed `mailto:` to the
   platform's contact address until a form exists.
