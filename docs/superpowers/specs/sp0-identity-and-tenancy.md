# SP-0 — Identity and tenancy

> **Status:** Approved for review · **Date:** 2026-08-29 · **Project:** the DOP platform
>
> **Answers:** who the user is, what an account is, how ownership and isolation work, and how
> one enters and leaves an account.
>
> **Does not answer:** integrations and credentials → [`sp0-integrations-and-credentials.md`](sp0-integrations-and-credentials.md).
> Decomposition and phasing → [`ROADMAP.md`](../../ROADMAP.md). Vocabulary →
> [`GLOSSARY.md`](../../GLOSSARY.md). Rationales → [`adr/`](../../adr/).

The base decisions: [ADR-0002](../../adr/0002-account-as-unit-of-ownership.md) (the account as
the unit of ownership), [ADR-0005](../../adr/0005-multi-tenant-platform.md) (multi-tenant),
[ADR-0004](../../adr/0004-organization-verification-by-domain.md) (verification by domain),
[ADR-0001](../../adr/0001-infrastructure-behind-ports.md) (ports),
[ADR-0027](../../adr/0027-second-factor-in-the-core.md) (the second factor).

## 1. Identity

**`User`** — the person's identity. The provider's identifier, e-mail, name, avatar and linked
providers. It exists once on the platform, regardless of how many accounts they reach.

Authentication uses **Firebase Authentication** as the `IdentityProvider` port's first adapter,
with four methods: e-mail and password, Google, GitHub and LinkedIn. That is the **first**
factor; the second is the platform's (§3, ADR-0027).

Per ADR-0001, the adapter returns a **normalized principal** — `subject`, `email`,
`emailVerified`, linked providers. A Firebase claim does not cross the domain's boundary.

**Account linking enabled from day one.** The same e-mail arriving through two providers
resolves to the same `User`. Without it, the person who signed in through Google and later
through GitHub becomes two users — and a duplicate in a multi-tenant system is not a cosmetic
annoyance, it is access confusion.

## 2. The account and ownership

**`Account`** — the unit of ownership and isolation:

| Field | |
|---|---|
| `kind` | `personal` or `organization` |
| `handle` | a unique identifier on the platform; individuals and companies share the same namespace |
| `displayName` | the display name |
| *(an organization)* | the company registration number, legal name, address, the domain verification's state |

**`Membership`** — the `User × Account` link, carrying a role. It is where all access control
lives.

At sign-up, the personal account is born together with the user: `kind: 'personal'`, a handle
derived from the e-mail, one `owner` membership. On a handle collision, it is suffixed until it
resolves; the user may change it later.

### 2.1 The shape of ownership

```
The platform
├── Personal account 01  (kind=personal, a root)  ─┐
├── Personal account 02  (kind=personal, a root)  ─┼─ they exist in their own right
└── Organization account (kind=organization)       │
      ├── a membership → 01   role: owner          │  the membership is a row,
      └── a membership → 02   role: developer     ─┘  not a copy and not nesting
```

The role lives **in the row**, not in the person: the same individual is `owner` in one
organization and `developer` in another with nothing changing in them.

**Two consequences of "a membership only":**

- The personal account's workspaces, projects and integrations **do not become** the
  organization's, nor the other way round. Each account owns its own; the membership gives
  access to what is the organization's and nothing more.
- Unlinking removes access to what is the organization's and **touches nothing** of what is the
  person's.

### 2.2 The active account

**Every API call carries an active account**, determined by a **selector** in the interface. It
is what decides what the user sees and where what they create ends up. A request with no active
account is invalid.

The selector lists the personal account plus every organization the user has a membership in.

## 3. The second factor

The platform is born with a second factor, and it is **the platform's** — the identity provider
does the first one and nothing else (ADR-0027). Three options, one mechanism:

| kind | How it verifies | Channel |
|---|---|---|
| `totp` | RFC 6238, 30 s, 6 digits, a ±1 window | none — the seed lives in the vault |
| `email` | a 6-digit code, 10 minutes, single use | the `Mailer` port (ADR-0025) |
| `sms` | the same code, the same validity | the `SMSer` port, born with this feature |

**Enrolment proves possession**: `enroll → challenge → confirm`. The factor is born `pending`
and only becomes `active` when the person returns the code — a factor registered without being
proven is a lock whose key nobody has tested. An `email` factor requires a **verified** address
(the `IdentityProvider`'s guarantee 5, the same one ADR-0026 leans on).

**Verification runs in the core**, because the TOTP seed is a credential and lives in the vault
(ADR-0023): the BFF forwards the challenge and the answer, and stores neither seed nor code. The
core records the step-up per (user, session) with an expiry, and the session identifier travels
in the metadata, alongside `x-actor-id` and `x-account-id`.

**What requires a fresh step-up, in v1:** signing in (when there is an active factor), writing a
credential (`SetCredential`), changing a role, inviting, revoking, and deleting an account.
Reading is not gated — a challenge on every request is theatre, and it teaches people to answer
without reading.

**Recovery codes are part of the feature, not a refinement.** Ten single-use codes, shown once,
kept hashed. Without them a lost phone becomes a support ticket, and support becomes the bypass.

**The account's policy.** An organization account may require a second factor of its members
(`require_second_factor`): a member with no active factor still signs in and operates their
personal account, but does not operate THAT one. For a personal account, enrolment is offered,
not imposed — a recorded assumption, open to the product's veto.

Enrolment, confirmation, success, failure, cool-off and recovery-code use are events (ADR-0006):
the timeline shows them, and no failure becomes an item in the attention box — a failed attempt
is not a decision for a human.

## 4. The membership's cycle

A membership is born of an **invite**. There is no other way in, except the automatic entry by
a verified organization's domain (§6).

**`Invite`**: `accountId`, `email`, `role`, grants, `invitedByUserId`, `status`, `expiresAt`.

```
pending ──acceptance──▶ accepted
   │
   ├──14 days──▶ expired
   └──revocation──▶ revoked
```

The rules:

- **The role and the grants are composed in the invite**, not afterwards. Whoever invites
  chooses freely: everything, nothing or a selection. After acceptance, everything is editable
  at any time.
- The invite is addressed to an **e-mail**. If a `User` with that e-mail already exists,
  acceptance creates the `Membership` directly; if not, acceptance goes through sign-up and the
  membership completes at its end.
- **It expires in 14 days.** Resending generates a new invite and invalidates the previous one.
- **Revocable while `pending`.**
- An invite to an e-mail that is already a member of that account is refused.

## 5. Roles and grants

Two independent axes.

**The role** — what the person may do *in the account*. One per `Membership`.

| Role | |
|---|---|
| `owner` | Full control, including billing, transferring ownership and deleting the account |
| `admin` | Manages members, integrations and workspaces. Everything but billing and deletion |
| `developer` | Works on the cards: runs them, talks to Claude, opens a PR. Does not manage members and does not create integrations |
| `viewer` | Read-only — following cards, seeing the dossier. It serves a PO and a manager |

An intermediate `maintainer` and a separate billing role were deliberately left out. A role is
a field in the membership: adding one later requires no migration, and inventing a hierarchy
nobody asked for is complexity you pay for without receiving.

**A resource grant** — per user, per resource (integrations, skills, workflows, git flows —
ADR-0013), with level `use` or `manage`. Orthogonal to the role; the mechanism is in
[`sp0-resources.md`](sp0-resources.md) and, for the case with a credential,
[`sp0-integrations-and-credentials.md`](sp0-integrations-and-credentials.md).

`owner` and `admin` have an implicit `manage` over every resource — without it you get the
scenario where nobody can fix a broken integration.

**There is no default.** Access is what was composed in the invite and what was edited
afterwards.

## 6. Succession and an orphaned account

**An invariant: every account has at least one active `owner`.** The system refuses any
operation that violates it, with an explicit message.

- An `owner` **may not** demote themselves or leave while they are the last one. They have to
  promote somebody else first.
- A personal account has exactly one membership, `owner`, not removable. Deleting it is
  deleting the user — see P-3 in `ROADMAP.md`.

**Recovering an orphaned organization** — the only `owner` became unreachable (they left the
company, lost access, died):

- If the organization is **verified by domain**, an `admin` claims ownership by **proving
  control of the domain again** — the same mechanism as ADR-0004. Resolved by the customer
  themselves, with no intervention.
- If it is **not verified**, there is no proof available. It stays open (P-6).

That reuse is one more argument for domain verification: it pays twice.

## 7. Organizations

**Creation.** A name and a company registration number; the number fills in the legal name and
the address automatically and already confirms the company exists and is active. The account is
born instantly, `kind: 'organization'`, and whoever created it becomes `owner`. No waiting, no
document.

**Domain verification.** Optional, done whenever the user wants: the platform generates a
value, the user publishes a TXT record in the company domain's DNS, the platform checks it.

**The verification unlocks three capabilities:**

- **automatic entry by domain** — any `@domain` e-mail gets in without an invite;
- the **verified badge**, with the domain in plain sight;
- **contesting a handle** taken by a third party.

And it serves as proof when recovering an orphaned account (§6).

Everything else works without the verification. An unverified organization is fully usable — it
just cannot make claims about itself that it has not proven.

## 8. The hierarchy

```
The platform (level 0)   the catalogue of providers, templates, skills — it belongs to nobody
   ╎
  The account (personal or organization)   cross-cutting: it owns and isolates
   └── Workspace (1)   a name, a key, a description, a tag schema
         └── Project (2)   repositories + the task manager's space
```

A project consumes the integrations of the **account that owns the workspace it is in**. Moving
a workspace to another account changes, in one go, the set of integrations available to all its
projects.

**A project does not compose integrations from different accounts.** If it did, answering "with
which credential was this done?" would stop being trivial — and that question is the dossier's
foundation.

## 9. Risks

| # | |
|---|---|
| R-1 | **A handle shared between individuals and companies** creates name contention. Mitigated by the contestation through a verified organization (§7) |
| R-2 | **Badly configured account linking creates duplicate users**, and a duplicate in multi-tenant becomes an access problem. It has to be active from day one (§1) |
| R-3 | **An invite by e-mail is a vector for internal phishing.** Acceptance has to require an authenticated session and show clearly which account is being entered |
| R-4 | **The `workspace → project` renaming** cuts across code, routes, i18n, mocks and documentation. Done halfway, it costs more than done in one go (P-5) |
| R-5 | **SMS is the weakest of the three factors** (SIM swap, interception) and the only one that costs money per attempt, which makes it the abuse surface: rate limiting per destination is a requirement, not a refinement (ADR-0027) |
| R-6 | **A forged session identifier skips the step-up.** The core trusts the BFF's metadata; the NetworkPolicy makes the assumption hold, and that is not the same as authenticating (P-18, which this feature promotes from background item to prerequisite) |
| R-7 | **A second factor with no recovery path locks people out**, and the workaround becomes a human being talked into resetting it. The recovery codes are what stop support from becoming the bypass |

## 10. Open items

Recorded in [`ROADMAP.md`](../../ROADMAP.md), each with its own decision:

- **P-1** — the audit trail of grants and memberships.
- **P-3** — data protection law: retention, deletion and residency, with personal and company
  registration numbers in scope.
- **P-6** — recovering an **unverified** orphaned organization.
- **P-18** — authenticating the caller between the BFF and the core, now load-bearing (R-6).
- **P-33** — the SMS provider and its second adapter, plus the cost and abuse ceiling.
- **P-34** — accepting a second factor asserted by the identity provider, when the account's
  policy allows it.
