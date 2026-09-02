# ADR-0005 — A multi-tenant platform with organizations

- **Status:** Accepted
- **Date:** 2026-08-29

## Context

The product's earlier documentation fixed the usage model as **single-user, multi-project in
parallel**, with no multi-user and no RBAC, and listed "multi-user with advanced RBAC"
explicitly out of scope. The product was understood as one developer's local tool.

The direction changed: the platform now has users with their own authentication,
organizations with members, roles and per-integration access control — running on a cluster
or in the cloud, not on somebody's machine.

## Decision

**Replace the earlier decision.** The platform is multi-tenant from the data model on:

- There is a `User`, with authentication by e-mail and password, Google, GitHub and
  LinkedIn.
- There is an `Account`, personal or organization
  ([ADR-0002](0002-account-as-unit-of-ownership.md)).
- **Every domain entity carries account, workspace and project from the first migration**,
  and every call at the edge is authenticated and resolves an active account.

The model is born complete even where the functionality does not exist yet — organizations,
members and roles come in a later phase **with no migration**, because the schema already
foresaw them.

## Alternatives considered

**Keep it single-user and add tenancy later.** Faster to reach the product. Rejected:
retrofitting multi-tenant isolation is one of the most expensive and risky migrations there
is — every query written without an account filter becomes a potential leak, and the cost
grows with the code base.

**Build everything before going back to the product's core.** Rejected for delaying the
product that justifies the platform too far. The middle ground adopted — model everything,
build authentication and the personal account — already exercises multi-tenancy for real,
because every query filters by account from the start; the account simply is always
personal.

## Consequences

- ➕ Correct isolation from the first line, without the most expensive migration in the
  catalogue.
- ➕ Organizations come in without touching the schema.
- ➖ A larger scope: authentication, accounts, roles and grants before any product value is
  delivered.
- ➖ Secrets become per-account, no longer global to the process.
- ➖ It brings personal and company registration numbers into the system, with the data
  protection obligations that implies (P-3 in `ROADMAP.md`).
