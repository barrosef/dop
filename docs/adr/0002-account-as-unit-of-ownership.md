# ADR-0002 — Tenancy: the account owns everything, and an organization proves itself by domain

- **Status:** Accepted
- **Date:** 2026-08-29 · **consolidated 2026-09-04**
- **Absorbs:** ADR-0004 (verifying an organization by domain) and ADR-0005 (a multi-tenant
  platform) — one subject, one ADR. Those numbers are **retired and never reused**.

## Context

Three questions arrived together, and answering them apart is what produced three documents.

**Who owns things.** Both an individual and an organization own integrations, workspaces and
projects. The requirements carried an apparent tension: integrations "can be seen and
manipulated only by that user", but a member linked to an organization "has controlled access
to all" of its integrations. A model was needed in which both statements were true at the same
time, with no special rule per case.

**When tenancy is built.** The product's earlier documentation fixed the usage model as
**single-user, multi-project in parallel**, with no multi-user and no RBAC — the platform was
understood as one developer's local tool. The direction changed: users with their own
authentication, organizations with members, roles and per-integration access control, running
on a cluster or in the cloud.

**How an organization proves it is one.** The original requirement asked, at creation, to
validate whether the signed-in user's national ID is the company's owner or holds a power of
attorney — citing GitHub and GCP as references for fluidity, with the explicit instruction
"do not invent, do not make it hard". We went to check what those references actually do:

- **GitHub** creates an organization instantly and for free, with **no ownership check
  whatsoever**. The verification exists afterwards, is of the **domain** (a TXT record in
  DNS), and earns the verified badge.
- **GCP** requires, to create the organization node, a Cloud Identity or Workspace account
  tied to a **verified domain** — also through DNS.

Neither asks for a national ID or a power of attorney. The requirement's two halves pull in
opposite directions: validating ownership *is* making it hard, and the references cited do not
do it.

## Decision

### 1. Multi-tenant from the data model on

- There is a `User`, with authentication by e-mail and password, Google, GitHub and LinkedIn.
- There is an `Account`, personal or organization.
- **Every domain entity carries account, workspace and project from the first migration**, and
  every call at the edge is authenticated and resolves an active account.

The model is born complete even where the functionality does not exist yet — organizations,
members and roles come in a later phase **with no migration**, because the schema already
foresaw them.

### 2. The account is the single unit of ownership

An **`Account`** entity with `kind: 'personal' | 'organization'`. Everything that is owned — an
integration, a workspace, a project — carries an `accountId`, and nothing else. The
user↔account link is a **`Membership`** carrying a role. At sign-up, the personal account is
born together with the user.

The requirements' tension **dissolves by construction**: a personal account's integration is
private because the account has a single member; an organization's integration is shared
because the account has several, under roles and grants. No code needs to know the difference.

Personal accounts and organizations are both roots of the platform and **share the same handle
namespace** — which is what makes §3 necessary.

### 3. Create instantly, verify the domain later, gate few capabilities on it

1. **Instant creation.** A name and a company registration number; the number fills in the
   legal name and address automatically and already confirms that the company exists and is
   active. No waiting, no document.
2. **Optional domain verification.** The platform generates a value, the user publishes a TXT
   record in the company domain's DNS, the platform checks it.
3. **The verification unlocks three capabilities**, deliberately few:
   - automatic entry by domain — any `@domain` e-mail gets in without an invite;
   - the verified badge, with the domain in plain sight;
   - contesting a handle taken by a third party.

Everything else works without the verification: integrations, individual invites, workspaces,
projects, execution. An unverified organization is fully usable — it just cannot make claims
about itself that it has not proven.

## Alternatives considered

**A polymorphic owner** — each resource keeping `ownerType: 'user' | 'org'` plus `ownerId`. It
models the requirements' text literally. Rejected: every query then needs two fields and a
branch; access rules end up written twice; and transferring a resource between a person and an
organization becomes a migration instead of an update. It is the model GitLab had and migrated
away from, towards *namespaces*, for these reasons.

**Nestable namespaces** — a generic tree with permission inheritance at any depth, in the style
of GitLab's *groups*. Rejected on YAGNI: the hierarchy asked for is fixed and three levels deep
(account → workspace → project). Building a generic tree to represent a fixed structure is
paying for the complexity of inheritance, cycles and permission resolution without having the
requirement.

**Keep it single-user and add tenancy later.** Faster to reach the product. Rejected:
retrofitting multi-tenant isolation is one of the most expensive and risky migrations there is
— every query written without an account filter becomes a potential leak, and the cost grows
with the code base.

**Build everything before going back to the product's core.** Rejected for delaying the product
that justifies the platform too far. The middle ground adopted — model everything, build
authentication and the personal account — already exercises multi-tenancy for real, because
every query filters by account from the start; the account simply is always personal.

**Validating ownership by national ID at creation** — checking whether the ID appears as a
partner or director of the company, or requiring a power of attorney. Rejected: it requires an
integration with a corporate-registry database, handles a power of attorney badly (a document
for a human to review) and creates friction exactly where fluidity was asked for.

**Free creation with no verification at all.** Maximum fluidity and the least effort. Rejected
because it leaves the handle dispute unanswered, which the shared namespace of §2 makes
inevitable.

## Consequences

- ➕ **A single isolation boundary**: every query filters on one field, from the first line,
  without the most expensive migration in the catalogue.
- ➕ Roles work the same for an individual and an organization — the personal account has one
  membership, `owner`. Organizations come in without touching the schema.
- ➕ Transferring a workspace between accounts is changing one value.
- ➕ The account selector lists the personal account and the organizations in the same place
  because they are the same thing.
- ➕ Zero paperwork and zero waiting at creation; the autofill by registration number *helps*
  instead of blocking, and control of a corporate domain is strong organizational evidence,
  resolved in minutes by the user themselves. Reusable: the same verification serves as proof
  when recovering an orphaned account.
- ➖ It creates an implicit personal account the user never asked for and may not notice.
- ➖ A shared handle creates name contention: if somebody takes `acme` as a personal account,
  the Acme organization cannot use it — mitigated, not removed, by §3.
- ➖ A larger scope: authentication, accounts, roles and grants before any product value is
  delivered. Secrets become per-account, no longer global to the process.
- ➖ It brings personal and company registration numbers into the system, with the data
  protection obligations that implies (P-3 in `ROADMAP.md`).
- ➖ **Domain verification does not prove legal representation.** Whoever controls the DNS is
  not necessarily whoever can sign for the company. If there is ever a contractual or tax
  obligation that requires it, that will be another decision, in another layer.
