# The onboarding journey — from "how do you want to enter" to "ready to fly"

- **Date:** 2026-09-20
- **Status:** decisions approved by the owner; revised the same day with five
  adjustments (§2 records them); spec under review
- **Supersedes:** `2026-09-06-profile-onboarding-design.md` (the five-step
  wizard). Its phone step is reborn as the contact step; its tools, social
  networks and referral steps are retired; its plans step is absorbed here.
- **Builds on:** `2026-09-06-account-signup-design.md` (the door — its rules
  stand unchanged), [ADR-0002](../../adr/0002-account-as-unit-of-ownership.md),
  [ADR-0003](../../adr/0003-organization-credential-human-authorship.md),
  [ADR-0009](../../adr/0009-resource-as-unit-of-sharing.md),
  [ADR-0010](../../adr/0010-dynamic-workflow.md) §8 (the platform catalogue),
  [ADR-0018](../../adr/0018-communication-trigger-and-channel.md),
  [ADR-0020](../../adr/0020-second-factor-in-the-core.md),
  [ADR-0022](../../adr/0022-the-core-verifies-its-callers.md)
- **Touches:** `dop-core`, `dop-api`, `dop-app`; `dop-infra` for the SMS
  channel's credential

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
- no profile editing, no default workspace, no plan, no connection to where
  the person's code and cards live.

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
on it. The journey builds nothing for it and does not show it either — the
person meets the flow on their first demand, where it means something.

**SMS is built.** `secondfactor.EnrollCode` sends a code through `ports.SMSer`
(Twilio and Zenvia adapters, one contract suite) and `Confirm` validates it.
The contact step enrols the phone as an SMS second factor, and verifying the
number is what enrolment already is.

## 2. Decisions

The first draft had the workspace and the photo on stage and connections after
the workspace. The owner's five adjustments, applied here: **(1)** connections
belong to the account and workspaces use them, so connections come first — and
the workspace is backstage, created but never a step; **(2)** photo and logo
are out of the journey, reachable later from the profile and the account;
**(3)** a phone is optional, verified by SMS when given, and an unverified
phone never blocks; **(4)** the final order is entry → profile → contact →
code → tasks → plan → ready, with profile, code and plan required;
**(5)** what is not verified is remembered in the attention box.

**D-1. The journey has seven moments and one goal: the person leaves it able to
create a project and start.** Entry → profile → contact → code connections →
task connections → plan → ready. Each moment is *explain → act → confirm*;
none is a bare form.

**D-2. State lives in the core, never in the browser.** `GET /me/onboarding`
answers where the person is and what is done; the cockpit routes to the next
undone step from any route until the journey is complete, and never again
after. A flag in `localStorage` is lost on another device and forged on this
one. This is the routing exception the wizard spec named (its D-6): the gate
protects nothing, so it stays in the cockpit; the *record* stays in the core.

**D-3. A personal account is born with a personal workspace — backstage.** The
rule is the core's, inside `EnsureUser`, idempotent: key `personal`, name from
the person's locale, created together with the personal account and never
duplicated. The journey does not show it; the person finds it in the tree.

**D-4. Connections are real integrations, not a catalogue of preferences.**
The wizard's "which tools do you use" is replaced by creating the actual
resource (`integration`, category `git` or `task_manager`, the provider's
credential in the vault). The provider list is data served by the API
(`GET /catalog/providers`), with each provider's credential method, required
permissions, whether it needs a base URL, and whether the platform **operates**
it today. GitHub and GitLab are operated; Bitbucket, Azure DevOps, Jira and
ClickUp are registered with their credential and labelled honestly as *not yet
operated*. Nothing in the cockpit knows that list.

**D-5. Required and optional, stated once.**

| step | required | why |
|---|---|---|
| `profile` | yes | name and handle are choices the person can always make |
| `contact` | no | a phone depends on a carrier; a step that can fail for reasons outside the person's control is never a locked door |
| `code` | **yes** | the owner's decision: without a code connection there is no first project, and the goal of the journey is the first project |
| `tasks` | no | cards can come later; the demand can be opened by hand |
| `plan` | yes | the owner's decision |

`complete` refuses while `profile`, `code` or `plan` is undone, and nothing
else. A skipped optional step shows on the rail as skipped, not as pending.

**D-6. A plan is chosen, and it carries no price.** Free, Start, Pro and
Enterprise from `plan_catalog`, Free pre-selected, the choice recorded on the
personal account (`accounts.plan_key`). No price is shown and no space is
left where one would go; Enterprise leads to a contact action. Billing is a
subsystem of its own and is not started here.

**D-7. A phone is optional; given, it is verified by SMS; unverified, it never
blocks.** The contact step takes the number, sends the code through the
second-factor enrolment that exists, and confirms it. If the code does not
arrive, the person resends, corrects the number, or moves on — the phone is
recorded as unverified and the reminder of D-8 takes over. The SMS channel is
whichever `ports.SMSer` adapter the environment wires; the OneSignal account
is pending on the owner's side and, when it lands, is a third adapter behind
the same port, not a change here.

**D-8. What is not verified is remembered in the attention box — by a
reaction, not by a screen.** An unverified phone raises an attention item
(*confirm your phone*) that closes itself when the number is confirmed. The
mechanism is ADR-0010's: a `reaction_rules` row per reminder, with the
`open_attention` and `close_attention` actions the registry already has,
reacting to `user.phone.added` and `secondfactor.confirmed`. They come alive
with P-29's dispatcher; until then the use case opens and closes the item
synchronously, on the same events, so the person sees the same thing.

The **e-mail is different, and stays at the door.** The sign-up spec's D-5
refuses a password credential whose e-mail is not verified — in the core, with
`412` — because with a password the e-mail is the only thing tying the
credential to a person. Somebody refused at the door never reaches the
attention box, so the e-mail's reminder is the *check your inbox* screen with
its resend. The reminder machinery is the same for both; relaxing the door to
"enter and be reminded" would be one rule row and a change to the sign-up
spec's D-5, which this spec does not make.

**D-9. Everything the person reads is the API's or the i18n map's.** Provider
permissions, plan taglines, error messages — none is a string in the cockpit.
`RAILS.md` §2 and §6 bind every screen here.

**D-10. Out of the journey, on purpose:** the photo and the account's logo
(reachable from the profile and the account screens; the upload mechanism is
later work), the workspace (D-3), referral (the code stays on the user; no
step), organization creation, billing, GitHub App installation for
organizations (ADR-0003 — a personal account uses a personal token).

## 3. The journey

The step rail is on the left and reflects `GET /me/onboarding`: done, current,
skipped, pending. Every step has a narrative panel that says what the step
does, what the platform will do with the answer, and — on optional steps —
what skipping costs. The portal is not visible behind the journey; there is
nothing in it yet worth dimming.

### 0 · Entry — `/sign-up`

Two halves. Left: the promise in three lines — connect your code, bring your
cards, the agent works on your flow. Right: *How do you want to enter?* —
Google, GitHub, e-mail. E-mail expands inline into address and password, with
strength feedback and the policy named **before** it is violated.

Everything the sign-up spec decided holds unchanged: linking on a second
provider (US-5), verification for a password credential refused in the core
(US-2, `412`), the three messages of its §5. The *check your inbox* screen
gains a visible resend countdown and *I typed the wrong address*.

### 1 · Who you are — `/welcome/profile` · required

Arrives pre-filled from the token: name, e-mail with a *verified* mark, the
provider's photo shown as it is. The person may change the display name, the
personal account's handle (derived from the e-mail, checked for availability
as typed), language and time zone (detected, confirmed), and a date of birth —
optional, with one line saying why it is asked. Required: name and handle.

### 2 · How to reach you — `/welcome/contact` · optional

A phone number, then the code, through second-factor enrolment. Resend with a
visibly growing delay, *correct my number* in place, and *skip* always visible
and never worded as failure. On skip, or on a code that never arrives, the
number stays recorded as unverified and D-8's reminder is raised.

### 3 · Where your code lives — `/welcome/code` · required

Tiles from `GET /catalog/providers`, category `git`: GitHub, GitLab, GitLab
self-hosted, Bitbucket, Azure DevOps. Selecting a tile opens a side panel with
that provider's method: the token kind, the exact permissions to grant
(listed, copyable), the base URL when the provider needs one, and a *test
connection* control. Each tile carries the API's status: *operated today* or
*registered — operation coming*. At least one connection is required to
continue; several may be made.

### 4 · Where your cards live — `/welcome/tasks` · optional

The same tiles and the same panel, category `task_manager`: Jira, ClickUp.
Skippable, with the narrative saying what a board connection buys (cards
become demands) and that it can be connected from the project later.

### 5 · How you want to start — `/welcome/plan` · required

Four plans side by side from `GET /catalog/plans`, each with name, tagline and
features; Free pre-selected; one must be chosen (D-6). Enterprise's action is
*talk to us*. No price, no gap.

### 6 · Ready to fly — `/welcome/ready`

A checklist: profile ✓, phone (verified / not verified / not given), code
connections *n*, task connections *n* (or *none*), plan ✓. One primary
action: **Create your first project** — which opens project creation already
choosing a repository from the connection made and, when a board is connected,
binding it. A secondary *Go to the cockpit*. Completing marks `onboarded_at`;
the journey never appears again.

## 4. The data

One migration in `dop-core`:

```
users        + birth_date date NULL
             + locale text NULL, timezone text NULL
             + phone text NULL, phone_verified_at timestamptz NULL
             + onboarding jsonb NOT NULL DEFAULT '{}'   -- {step: done|skipped, ...}
             + onboarded_at timestamptz NULL
accounts     + plan_key text NULL REFERENCES plan_catalog(key)
plan_catalog   key PK, name, tagline, features jsonb, sort, active
provider_catalog
               key PK, category (git|task_manager), name, credential_kind,
               permissions text[], needs_base_url bool, operated bool,
               docs_url, brand_color, sort, active
reaction_rules + the two platform rows of D-8 (open on user.phone.added,
                 close on secondfactor.confirmed)
```

`phone_verified_at` is written by the second-factor confirmation of a factor
whose destination equals `users.phone`; it is the only writer. `phone` is
written by `PATCH /me` and cleared when the person removes it.

Both catalogues are seeded from `repos/dop-core/seed/catalog.yml` by
`make seed-catalog` — an upsert by key, so editing a tagline is a re-run, not
a migration. Removing an entry sets `active=false`.

Initial provider rows: `github`, `gitlab`, `gitlab_self_hosted` (needs base
URL), `bitbucket`, `azure_devops` in `git`; `jira`, `clickup` in
`task_manager`. `operated=true` only for `github` and `gitlab`.

## 5. The contract

| need | operation | notes |
|---|---|---|
| journey state | `GET /me/onboarding` | steps with status, `email_verified`, `phone`, `phone_verified`, `code_connections`, `task_connections`, `plan_key`, `complete` |
| record a step | `POST /me/onboarding/steps/{step}` body `{status: done\|skipped}` | the core validates the step name; `skipped` only for `contact` and `tasks` (D-5) |
| finish | `POST /me/onboarding/complete` | sets `onboarded_at`; refused naming the undone required step |
| profile | `PATCH /me` | `name`, `birth_date`, `locale`, `timezone`, `phone` |
| phone code | `POST /me/second-factor/factors` · `POST …/verify` | exist today (ADR-0020); the confirmation writes `phone_verified_at` |
| personal account | `PATCH /accounts/current` (`display_name`, `handle`) · `GET /accounts/handles/{handle}/availability` | handle rules as today (`NormalizeHandle`) |
| providers | `GET /catalog/providers` | grouped by category, ordered |
| connection | `POST /resources` · `PUT /resources/{id}/credential` | exist today |
| test | `POST /resources/{id}/check` | github/gitlab call the provider (`whoami`); others answer `{operated:false}` with a message |
| plans | `GET /catalog/plans` · `PUT /accounts/current/plan` body `{plan_key}` | Enterprise is a valid choice; the contact is a link |
| reminder | the attention box, as today | the item kind `contact.phone.unverified`, opened and closed by D-8 |

`MeResponse` gains `avatar_url`, `locale`, `timezone`, `phone`,
`phone_verified`, `onboarded`. `AccountSummary` gains `plan_key`.

Nothing changes in `Principal`, in the identity adapters or in the
verification contract. `make proto-breaking` must stay green: every addition
is a new field or a new RPC.

## 6. What changes, by repository

**`dop-core`** — the migration and the seed; `EnsureUser` creates the personal
workspace (D-3); `identity` gains profile update and onboarding state;
`secondfactor` writes `phone_verified_at` on confirming a factor whose
destination is the user's phone; `resource` gains `Check` (the `gitprovider`
port already has what `whoami` needs for GitHub and GitLab); `catalog` is a
small new domain (read-only over two tables); `attention` gains the item kind
of D-8 and the two rules. Domain tests for D-3's idempotence, the step
validation, `complete` refusing undone required steps, `Check` on a
non-operated provider, and the reminder opening and closing.

**`dop-api`** — the routes of §5, use cases first (REST and gRPC share them),
no state, no secret.

**`dop-app`** — after `fetch-spec` + `codegen`: the seven screens, the rail,
the gate from any route (D-2), the provider panel. Its own spec
(`repos/dop-app/docs/superpowers/specs/`) is written from this one and is what
the Replit prompt carries — screen by screen, with the generated hooks named.
It is written **after** the contract is on QA, never before.

**`dop-infra`** — the SMS adapter's credential for QA, in the vault, with its
row in the ADR-0015 §4 ownership table; OneSignal when the account exists.

## 7. Errors the person sees

- **handle taken** — inline, as typed, with a suggestion; never on submit;
- **code did not arrive** — resend with the delay visible, the number editable
  in place, and skip; **wrong code** — say so and show attempts remaining;
  **rate limit** — say when, not "an error occurred";
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
- end to end on QA before release: Google sign-in → profile → skip contact →
  GitHub token through `Check` → skip tasks → Free → ready → first project;
  and the phone path once an SMS adapter has a QA credential.

## 9. What this does not build

Billing and prices; photo and logo upload; the GitHub App path for
organizations; operating Bitbucket, Azure DevOps, Jira or ClickUp; the
OneSignal SMS adapter; referral rewards; organization creation; editing the
catalogues from a screen; relaxing the e-mail door (D-8).

## 10. Open items

1. Plan taglines and feature lists need the owner's words; the seed carries a
   first draft.
2. The Enterprise contact — an e-mail or a form; proposed `mailto:` to the
   platform's contact address until a form exists.
3. Which SMS adapter QA uses until OneSignal exists — Twilio or Zenvia both
   need a credential the owner holds.
