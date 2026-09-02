# ADR-0002 — The account as the single unit of ownership and isolation

- **Status:** Accepted
- **Date:** 2026-08-29

## Context

Both an individual and an organization own integrations, workspaces and projects. The
requirements carried an apparent tension: integrations "can be seen and manipulated only by
that user", but a member linked to an organization "has controlled access to all" of its
integrations.

A model was needed in which both statements were true at the same time, with no special
rule per case.

## Decision

An **`Account`** entity with `kind: 'personal' | 'organization'`. Everything that is owned
— an integration, a workspace, a project — carries an `accountId`, and nothing else. The
user↔account link is a **`Membership`** carrying a role. At sign-up, the personal account
is born together with the user.

The requirements' tension **dissolves by construction**: a personal account's integration is
private because the account has a single member; an organization's integration is shared
because the account has several, under roles and grants. No code needs to know the
difference.

Personal accounts and organizations are both roots of the platform and **share the same
handle namespace**.

## Alternatives considered

**A polymorphic owner** — each resource keeping `ownerType: 'user' | 'org'` plus `ownerId`.
It models the requirements' text literally. Rejected: every query then needs two fields and
a branch; access rules end up written twice; and transferring a resource between a person
and an organization becomes a migration instead of an update. It is the model GitLab had
and migrated away from, towards *namespaces*, for these reasons.

**Nestable namespaces** — a generic tree with permission inheritance at any depth, in the
style of GitLab's *groups*. Rejected on YAGNI: the hierarchy asked for is fixed and three
levels deep (account → workspace → project). Building a generic tree to represent a fixed
structure is paying for the complexity of inheritance, cycles and permission resolution
without having the requirement.

## Consequences

- ➕ **A single isolation boundary**: every query filters on one field.
- ➕ Roles work the same for an individual and an organization — the personal account has one
  membership, `owner`.
- ➕ Transferring a workspace between accounts is changing one value.
- ➕ The account selector lists the personal account and the organizations in the same place
  because they are the same thing.
- ➖ It creates an implicit personal account the user never asked for and may not notice.
- ➖ A shared handle creates name contention: if somebody takes `acme` as a personal account,
  the Acme organization cannot use it. Mitigated by
  [ADR-0004](0004-organization-verification-by-domain.md).
