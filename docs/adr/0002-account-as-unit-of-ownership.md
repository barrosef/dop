# ADR-0002 — Tenancy: the account owns everything, and an organization proves itself by domain

- **Status:** Accepted
- **Date:** 2026-08-29
- **Relations:** refined by ADR-0009 (the resource as the unit of sharing); relied on by ADR-0019, ADR-0020

## Context

The platform is multi-tenant: users with their own authentication;
organizations with members, roles and per-resource access; both individuals
and organizations own integrations, workspaces and projects. An organization
must be creatable without paperwork and still able to prove it is the
company it claims to be.

## Decision

1. **Entities.** `User` (authentication by e-mail/password, Google, GitHub,
   LinkedIn); `Account` with `kind: personal | organization`; `Membership`
   (user ↔ account, with a role). A personal account is created with the
   user at sign-up.
2. **The account is the single unit of ownership.** Everything owned — an
   integration, a workspace, a project — carries an `account_id` and no other
   owner field. Every domain table carries `account_id` from the first
   migration; every call at the edge is authenticated and resolves an active
   account.
3. **The hierarchy is fixed and three levels deep:** account → workspace →
   project.
4. **Personal and organization accounts share one handle namespace.**
5. **Organization creation is instant:** a name and a company registration
   number; the number autofills the legal name and address.
6. **Domain verification is optional and later:** the platform issues a
   value, the account publishes it as a DNS TXT record, the platform checks
   it. Verification unlocks exactly three capabilities: automatic entry for
   any `@domain` e-mail, the verified badge, and contesting a handle held by
   a third party. Everything else works unverified.
7. **Phase 1 builds** authentication, the personal account and the
   workspace → project hierarchy. Organizations, members, roles, grants and
   verification are modelled now and built later without a migration.

## Alternatives considered

- **A polymorphic owner** (`owner_type` + `owner_id`) — rejected: two fields
  and a branch in every query; a transfer becomes a migration.
- **Nestable namespaces** — rejected: the hierarchy is fixed.
- **Single-user first, tenancy later** — rejected: retrofitting isolation.
- **Ownership validated by national ID / power of attorney at creation** —
  rejected: friction and a registry integration; no reference product does it.
- **No verification at all** — rejected: the shared handle namespace needs a
  dispute path.

## Consequences

- One isolation filter (`account_id`) everywhere.
- Roles are uniform: a personal account has one membership, `owner`.
- Transferring a workspace between accounts is a single-value update.
- Handle contention between personal accounts and organizations is
  mitigated by verification, not removed.
- Personal and company registration numbers enter the system (data
  protection — `ROADMAP.md` P-3).
- Domain verification proves control of DNS, not legal representation.

## Revisions

- 2026-09-04 — consolidated three records into one (verification by domain;
  multi-tenant model).
